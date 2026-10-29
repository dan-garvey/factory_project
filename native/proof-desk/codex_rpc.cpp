#include "codex_rpc.hpp"
#include <algorithm>
#include <cctype>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <fstream>
#include <netinet/in.h>
#include <openssl/evp.h>
#include <openssl/rand.h>
#include <poll.h>
#include <sstream>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

namespace factory::proof {
namespace {
std::string base64(const unsigned char *data, size_t size) {
  std::string value(4 * ((size + 2) / 3), '\0');
  EVP_EncodeBlock(reinterpret_cast<unsigned char *>(value.data()), data,
                  static_cast<int>(size));
  return value;
}
struct Socket {
  int fd = -1;
  std::chrono::steady_clock::time_point deadline =
      std::chrono::steady_clock::now() + std::chrono::seconds(15);
  size_t received = 0;
  ~Socket() {
    if (fd >= 0)
      close(fd);
  }
  void ready(short events) {
    auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(
                         deadline - std::chrono::steady_clock::now())
                         .count();
    require(remaining > 0,
            "Codex control timed out; mutation outcome is uncertain");
    pollfd p{fd, events, 0};
    require(poll(&p, 1, static_cast<int>(remaining)) > 0,
            "Codex control timed out; mutation outcome is uncertain");
  }
  std::string read(size_t count) {
    // Bound total traffic separately from a single message so initialization
    // and intervening events do not consume the image receipt's size budget.
    require(count <= 2 * codex_message_limit - received,
            "Codex connection exceeds 128 MiB");
    received += count;
    std::string out(count, '\0');
    size_t done = 0;
    while (done < count) {
      auto n = recv(fd, out.data() + done, count - done, 0);
      if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
        ready(POLLIN);
        continue;
      }
      require(n > 0, "Codex closed its control connection");
      done += n;
    }
    return out;
  }
  void write(const std::string &data) {
    size_t done = 0;
    while (done < data.size()) {
      auto n = send(fd, data.data() + done, data.size() - done, MSG_NOSIGNAL);
      if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
        ready(POLLOUT);
        continue;
      }
      require(n > 0, "Codex control write failed");
      done += n;
    }
  }
  void frame(unsigned opcode, const std::string &data) {
    require(data.size() < 65536, "Oversized control request");
    std::string packet;
    packet.push_back(static_cast<char>(0x80 | opcode));
    if (data.size() < 126)
      packet.push_back(static_cast<char>(0x80 | data.size()));
    else {
      packet.push_back(static_cast<char>(0xfe));
      packet.push_back(static_cast<char>(data.size() >> 8));
      packet.push_back(static_cast<char>(data.size() & 255));
    }
    unsigned char mask[4];
    require(RAND_bytes(mask, 4) == 1, "WebSocket mask failed");
    packet.append(reinterpret_cast<char *>(mask), 4);
    for (size_t i = 0; i < data.size(); ++i)
      packet.push_back(data[i] ^ mask[i % 4]);
    write(packet);
  }
  void json(const Json &value) { frame(1, value.dump()); }
  Json response() {
    std::string message;
    bool fragmented = false;
    for (;;) {
      auto head = read(2);
      auto first = static_cast<unsigned char>(head[0]),
           second = static_cast<unsigned char>(head[1]);
      bool fin = first & 0x80;
      unsigned op = first & 15;
      require(!(first & 0x70) && !(second & 0x80),
              "Invalid server WebSocket flags");
      uint64_t length = second & 127;
      if (length == 126) {
        auto b = read(2);
        length = (static_cast<unsigned char>(b[0]) << 8) |
                 static_cast<unsigned char>(b[1]);
      } else if (length == 127) {
        auto b = read(8);
        length = 0;
        for (unsigned char c : b)
          length = (length << 8) | c;
      }
      require(length <= codex_message_limit,
              "Codex WebSocket frame exceeds 64 MiB (" +
                  std::to_string(length) + " bytes)");
      if (op >= 8)
        require(fin && length <= 125, "Invalid WebSocket control frame");
      else
        require(length <= codex_message_limit - message.size(),
                "Codex WebSocket message exceeds 64 MiB");
      auto payload = read(static_cast<size_t>(length));
      if (op == 8)
        throw std::runtime_error("Codex closed the WebSocket");
      if (op == 9) {
        frame(10, payload);
        continue;
      }
      if (op == 10)
        continue;
      require((op == 1 && !fragmented) || (op == 0 && fragmented),
              "Unexpected WebSocket message type");
      message += payload;
      if (fin)
        return Json::parse(message);
      fragmented = true;
    }
  }
};
} // namespace
Json codex_rpc(const fs::path &socket, const std::string &method,
               const Json &params) {
  bool sent = false;
  try {
    // Linux abstract endpoints let isolated test peers use IPC without putting
    // sockets inside the build runner's measured regular-file artifact tree.
    const auto endpoint = socket.string();
    const bool abstract = !endpoint.empty() && endpoint.front() == '@';
    require(socket.is_absolute() || abstract,
            "Configure the running Codex daemon socket");
    sockaddr_un address{};
    address.sun_family = AF_UNIX;
    require(socket.string().size() < sizeof(address.sun_path),
            "Codex socket path is too long");
    std::strcpy(address.sun_path, socket.c_str());
    socklen_t addressLength = sizeof(address);
    if (abstract) {
      address.sun_path[0] = '\0';
      addressLength = offsetof(sockaddr_un, sun_path) + endpoint.size();
    }
    Socket connection;
    connection.fd =
        ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
    require(connection.fd >= 0, "Cannot open Codex control socket");
    if (connect(connection.fd, reinterpret_cast<sockaddr *>(&address),
                addressLength) != 0) {
      require(errno == EINPROGRESS,
              "Cannot connect to the running Codex daemon");
      connection.ready(POLLOUT);
      int error = 0;
      socklen_t size = sizeof(error);
      getsockopt(connection.fd, SOL_SOCKET, SO_ERROR, &error, &size);
      require(error == 0, "Codex daemon connection failed");
    }
    unsigned char random[16];
    require(RAND_bytes(random, 16) == 1, "Handshake key failed");
    auto key = base64(random, 16);
    connection.write(
        "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: "
        "websocket\r\nConnection: "
        "Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: " +
        key + "\r\n\r\n");
    std::string headers;
    while (headers.find("\r\n\r\n") == std::string::npos) {
      require(headers.size() < 8192, "Oversized WebSocket upgrade");
      headers += connection.read(1);
    }
    auto challenge = key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    unsigned char hash[EVP_MAX_MD_SIZE];
    unsigned size = 0;
    require(EVP_Digest(challenge.data(), challenge.size(), hash, &size,
                       EVP_sha1(), nullptr) == 1 &&
                size == 20,
            "Cannot verify WebSocket handshake");
    auto header = [&](const std::string &name) {
      size_t start = headers.find("\r\n") + 2;
      std::string found;
      while (start < headers.size() - 2) {
        auto end = headers.find("\r\n", start),
             colon = headers.find(':', start);
        require(colon < end, "Malformed WebSocket response header");
        auto key = headers.substr(start, colon - start);
        std::transform(key.begin(), key.end(), key.begin(),
                       [](unsigned char c) { return std::tolower(c); });
        if (key == name) {
          require(found.empty(), "Duplicate WebSocket response header");
          auto valueStart = headers.find_first_not_of(" \t", colon + 1);
          auto valueEnd = headers.find_last_not_of(" \t", end - 1);
          if (valueStart < end)
            found = headers.substr(valueStart, valueEnd - valueStart + 1);
        }
        start = end + 2;
      }
      return found;
    };
    require(headers.rfind("HTTP/1.1 101 ", 0) == 0 &&
                header("sec-websocket-accept") == base64(hash, size),
            "Codex WebSocket upgrade was not verified");
    connection.json(Json{{"id", 1},
                         {"method", "initialize"},
                         {"params",
                          {{"clientInfo",
                            {{"name", "factory_proof_desk"},
                             {"title", "Factory Proof Desk"},
                             {"version", "1.0"}}},
                           {"capabilities", {{"experimentalApi", true}}}}}});
    for (;;) {
      auto response = connection.response();
      if (!response.contains("id") || !response["id"].is_number_integer())
        continue;
      if (response["id"] != 1 && response["id"] != 2)
        continue;
      if (response.contains("error")) {
        const auto code = response.at("error").value("code", 0);
        const bool rejectedBeforeExecution =
            code == -32600 || code == -32601 || code == -32602;
        throw RpcFailure("Codex refused " + method + ": " +
                             response.at("error").dump(),
                         sent && !rejectedBeforeExecution);
      }
      if (response["id"] == 1) {
        connection.json(
            Json{{"method", "initialized"}, {"params", Json::object()}});
        sent = true;
        connection.json(
            Json{{"id", 2}, {"method", method}, {"params", params}});
      }
      if (response["id"] == 2)
        return response.at("result");
    }
  } catch (const RpcFailure &) {
    throw;
  } catch (const std::exception &error) {
    throw RpcFailure(method + ": " + error.what(), sent);
  }
}
bool is_antigravity_endpoint(const std::string &endpoint) {
  return endpoint.rfind("http://", 0) == 0;
}
Json antigravity_rpc(const std::string &endpoint, const std::string &method,
                     const Json &params) {
  bool sent = false;
  try {
    require(is_antigravity_endpoint(endpoint),
            "Configure the running Antigravity language server endpoint");
    const auto rest = endpoint.substr(7);
    const auto hash = rest.find('#');
    require(hash != std::string::npos && hash > 0 && hash + 1 < rest.size(),
            "Antigravity endpoint requires host:port and CSRF token");
    const auto authority = rest.substr(0, hash);
    const auto csrf = rest.substr(hash + 1);
    const auto colon = authority.rfind(':');
    require(colon != std::string::npos && colon > 0 &&
                colon + 1 < authority.size(),
            "Antigravity endpoint requires host:port");
    const auto host = authority.substr(0, colon);
    const auto portText = authority.substr(colon + 1);
    require(host == "127.0.0.1" || host == "localhost",
            "Antigravity endpoint must use loopback host");
    int port = 0;
    size_t parsedPort = 0;
    try {
      port = std::stoi(portText, &parsedPort);
    } catch (const std::exception &) {
      throw std::runtime_error("Invalid Antigravity port");
    }
    require(parsedPort == portText.size() && port > 0 && port <= 65535,
            "Invalid Antigravity port");
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_port = htons(static_cast<uint16_t>(port));
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    Socket connection;
    connection.fd =
        ::socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
    require(connection.fd >= 0, "Cannot open Antigravity control socket");
    if (connect(connection.fd, reinterpret_cast<sockaddr *>(&address),
                sizeof(address)) != 0) {
      require(errno == EINPROGRESS,
              "Cannot connect to the running Antigravity language server");
      connection.ready(POLLOUT);
      int error = 0;
      socklen_t size = sizeof(error);
      getsockopt(connection.fd, SOL_SOCKET, SO_ERROR, &error, &size);
      require(error == 0, "Antigravity language server connection failed");
    }
    const auto payload = params.dump();
    require(payload.size() <= codex_message_limit,
            "Oversized Antigravity control request");
    std::ostringstream request;
    request << "POST /exa.language_server_pb.LanguageServerService/" << method
            << " HTTP/1.1\r\nHost: " << authority
            << "\r\nContent-Type: application/json\r\n"
            << "Connect-Protocol-Version: 1\r\n"
            << "x-codeium-csrf-token: " << csrf
            << "\r\nContent-Length: " << payload.size()
            << "\r\nConnection: close\r\n\r\n"
            << payload;
    sent = true;
    connection.write(request.str());
    std::string headers;
    while (headers.find("\r\n\r\n") == std::string::npos) {
      require(headers.size() < 8192, "Oversized Antigravity HTTP headers");
      headers += connection.read(1);
    }
    const auto lineEnd = headers.find("\r\n");
    require(lineEnd != std::string::npos, "Malformed HTTP status line");
    std::istringstream statusStream(headers.substr(0, lineEnd));
    std::string httpVersion;
    int status = 0;
    statusStream >> httpVersion >> status;
    require(httpVersion.rfind("HTTP/1.", 0) == 0 && status >= 100 &&
                status <= 599,
            "Malformed Antigravity HTTP status");
    auto header = [&](const std::string &name) {
      size_t start = lineEnd + 2;
      std::string found;
      while (start < headers.size() - 2) {
        auto end = headers.find("\r\n", start),
              sep = headers.find(':', start);
        require(sep < end, "Malformed HTTP response header");
        auto key = headers.substr(start, sep - start);
        std::transform(key.begin(), key.end(), key.begin(),
                       [](unsigned char c) { return std::tolower(c); });
        if (key == name) {
          auto valueStart = headers.find_first_not_of(" \t", sep + 1);
          auto valueEnd = headers.find_last_not_of(" \t", end - 1);
          if (valueStart < end)
            found = headers.substr(valueStart, valueEnd - valueStart + 1);
        }
        start = end + 2;
      }
      return found;
    };
    std::string body;
    const auto contentLength = header("content-length");
    auto transferEncoding = header("transfer-encoding");
    std::transform(transferEncoding.begin(), transferEncoding.end(),
                   transferEncoding.begin(),
                   [](unsigned char c) { return std::tolower(c); });
    if (!contentLength.empty()) {
      uint64_t length = 0;
      size_t parsedLen = 0;
      try {
        length = std::stoull(contentLength, &parsedLen);
      } catch (const std::exception &) {
        throw std::runtime_error("Invalid HTTP Content-Length");
      }
      require(parsedLen == contentLength.size(), "Invalid HTTP Content-Length");
      require(length <= codex_message_limit,
              "Antigravity HTTP response exceeds 64 MiB (" +
                  std::to_string(length) + " bytes)");
      if (length > 0)
        body = connection.read(static_cast<size_t>(length));
    } else if (transferEncoding.find("chunked") != std::string::npos) {
      for (;;) {
        std::string chunkLine;
        while (chunkLine.find("\r\n") == std::string::npos) {
          require(chunkLine.size() < 128, "Malformed HTTP chunk header");
          chunkLine += connection.read(1);
        }
        const auto semi = chunkLine.find_first_of(";\r", 0);
        uint64_t chunkSize = 0;
        size_t parsedChunk = 0;
        try {
          chunkSize = std::stoull(chunkLine.substr(0, semi), &parsedChunk, 16);
        } catch (const std::exception &) {
          throw std::runtime_error("Malformed HTTP chunk size");
        }
        require(parsedChunk == semi && chunkSize <= codex_message_limit &&
                    chunkSize <= codex_message_limit - body.size(),
                "Antigravity HTTP response exceeds 64 MiB");
        if (chunkSize == 0) {
          require(connection.read(2) == "\r\n",
                  "Malformed HTTP chunk terminator");
          break;
        }
        body += connection.read(static_cast<size_t>(chunkSize));
        require(connection.read(2) == "\r\n", "Malformed HTTP chunk boundary");
      }
    }
    if (status != 200) {
      bool rejectedBeforeExecution =
          status == 400 || status == 401 || status == 403 || status == 404 ||
          status == 405 || status == 415;
      if (!body.empty()) {
        try {
          const auto err = Json::parse(body);
          const auto code = err.value("code", std::string());
          if (code == "invalid_argument" || code == "unauthenticated" ||
              code == "permission_denied" || code == "not_found" ||
              code == "unimplemented")
            rejectedBeforeExecution = true;
        } catch (const std::exception &) {
        }
      }
      throw RpcFailure("Antigravity refused " + method + " (HTTP " +
                           std::to_string(status) + "): " + body,
                       sent && !rejectedBeforeExecution);
    }
    return body.empty() ? Json::object() : Json::parse(body);
  } catch (const RpcFailure &) {
    throw;
  } catch (const std::exception &error) {
    throw RpcFailure(method + ": " + error.what(), sent);
  }
}
Json antigravity_deliver(const std::string &endpoint, const std::string &thread,
                         const std::string &client_id, const std::string &text,
                         const std::vector<std::string> &images) {
  Json trajectory;
  try {
    trajectory = antigravity_rpc(endpoint, "GetCascadeTrajectory",
                                 Json{{"cascadeId", thread}});
  } catch (const std::exception &error) {
    // GetCascadeTrajectory is read-only; failure before SendUserCascadeMessage
    // never mutates the conversation.
    throw RpcFailure(error.what(), false);
  }
  Json cascadeConfig = nullptr;
  Json customAgentSpec = nullptr;
  const auto steps = trajectory.value("trajectory", Json::object())
                         .value("steps", Json::array());
  for (auto it = steps.rbegin(); it != steps.rend(); ++it) {
    if (it->value("type", std::string()) != "CORTEX_STEP_TYPE_USER_INPUT" ||
        !it->contains("userInput"))
      continue;
    const auto &userInput = it->at("userInput");
    if (userInput.contains("userConfig") && !userInput.at("userConfig").is_null())
      cascadeConfig = userInput.at("userConfig");
    if (userInput.contains("userAgentSpec") &&
        !userInput.at("userAgentSpec").is_null())
      customAgentSpec = userInput.at("userAgentSpec");
    break;
  }
  Json req{{"cascadeId", thread},
           {"items", Json::array({Json{{"text", text}}})},
           {"deliveryStrategy", "MESSAGE_DELIVERY_STRATEGY_WHEN_IDLE"}};
  if (!cascadeConfig.is_null())
    req["cascadeConfig"] = cascadeConfig;
  if (!customAgentSpec.is_null())
    req["customAgentSpec"] = customAgentSpec;
  if (!images.empty()) {
    Json media = Json::array();
    for (const auto &path : images) {
      std::ifstream in(path, std::ios::binary);
      require(in.good(), "Cannot read marked feedback image: " + path);
      std::ostringstream buffer;
      buffer << in.rdbuf();
      const auto bytes = buffer.str();
      media.push_back(
          Json{{"mimeType", "image/png"},
               {"inlineData",
                base64(reinterpret_cast<const unsigned char *>(bytes.data()),
                       bytes.size())}});
    }
    req["media"] = media;
  }
  const auto response =
      antigravity_rpc(endpoint, "SendUserCascadeMessage", req);
  Json state{
      {"status", "delivered"},
      {"detail", "Review delivered to the originating Antigravity conversation"},
      {"client_message_id", client_id}};
  if (response.contains("queued_submission_id"))
    state["queued_submission_id"] = response.at("queued_submission_id");
  return state;
}
Json pause_for_review(const Json &config, const std::string &thread) {
  const auto endpoint = config.at("socket").get<std::string>();
  if (is_antigravity_endpoint(endpoint)) {
    const auto result = antigravity_rpc(endpoint, "GetCascadeTrajectory",
                                        Json{{"cascadeId", thread}});
    require(result.contains("trajectory"),
            "Antigravity conversation trajectory not found");
    return Json{{"paused_by_review", false}, {"runtime", "antigravity"}};
  }
  fs::path socket(endpoint);
  auto result =
      codex_rpc(socket, "thread/goal/get", Json{{"threadId", thread}});
  auto goal = result.value("goal", Json());
  if (goal.is_null() || goal.at("status") != "active")
    return Json{{"paused_by_review", false}};
  auto paused =
      codex_rpc(
          socket, "thread/goal/set",
          Json{{"threadId", thread}, {"status", "paused"}, {"origin", "user"}})
          .at("goal");
  require(paused.at("status") == "paused",
          "Review did not pause automatic goal continuation");
  return Json{{"paused_by_review", true},
              {"objective", goal.at("objective")},
              {"createdAt", goal.at("createdAt")}};
}
void resume_after_review(const Json &config, const std::string &thread,
                         const Json &paused) {
  if (!paused.value("paused_by_review", false))
    return;
  fs::path socket(config.at("socket").get<std::string>());
  auto goal = codex_rpc(socket, "thread/goal/get", Json{{"threadId", thread}})
                  .at("goal");
  if (goal.is_null() || goal.at("status") != "paused" ||
      goal.at("objective") != paused.at("objective") ||
      goal.at("createdAt") != paused.at("createdAt"))
    return;
  if (goal.contains("tokenBudget") && !goal.at("tokenBudget").is_null() &&
      goal.at("tokensUsed").get<int64_t>() >=
          goal.at("tokenBudget").get<int64_t>())
    return;
  // The explicit human decision resumes only the goal this proof paused; it
  // never changes objectives, budgets, usage-limited or budget-limited states.
  codex_rpc(
      socket, "thread/goal/set",
      Json{{"threadId", thread}, {"status", "active"}, {"origin", "user"}});
}
bool reconcile_delivery(const Json &config, const fs::path &bundle) {
  auto m = read_json(bundle / "manifest.json"),
       d = read_json(bundle / "decision.json");
  auto marker = "[proof-decision:" + d.at("id").get<std::string>() + "]";
  const auto endpoint = config.at("socket").get<std::string>();
  if (is_antigravity_endpoint(endpoint)) {
    const auto result = antigravity_rpc(
        endpoint, "GetCascadeTrajectory", Json{{"cascadeId", m.at("thread")}});
    auto stepMatches = [&](const Json &step) {
      if (step.value("type", std::string()) != "CORTEX_STEP_TYPE_USER_INPUT" ||
          !step.contains("userInput"))
        return false;
      const auto &userInput = step.at("userInput");
      if (userInput.value("userResponse", std::string()).find(marker) !=
          std::string::npos)
        return true;
      for (const auto &item : userInput.value("items", Json::array()))
        if (item.value("text", std::string()).find(marker) != std::string::npos)
          return true;
      return false;
    };
    for (const auto &step : result.value("queuedSteps", Json::array())) {
      if (!stepMatches(step))
        continue;
      const auto queuedId = step.value("metadata", Json::object())
                                .value("executionId", std::string("queued"));
      write_json(bundle / "delivery.json",
                 Json{{"status", "delivered"},
                      {"detail", "Confirmed in the originating Antigravity "
                                 "conversation queue"},
                      {"queued_submission_id", queuedId}});
      return true;
    }
    const auto steps = result.value("trajectory", Json::object())
                           .value("steps", Json::array());
    for (auto it = steps.rbegin(); it != steps.rend(); ++it) {
      if (!stepMatches(*it))
        continue;
      const auto itemId =
          it->value("metadata", Json::object())
              .value("executionId", std::string("antigravity-user-step"));
      write_json(bundle / "delivery.json",
                 Json{{"status", "delivered"},
                      {"detail", "Reconciled against the exact originating "
                                 "Antigravity user step"},
                      {"item", itemId}});
      return true;
    }
    return false;
  }
  Json queuedParams{{"threadId", m.at("thread")}, {"limit", 100}};
  for (int page = 0; page < 5; ++page) {
    auto result = codex_rpc(endpoint, "thread/queue/list", queuedParams);
    for (const auto &entry : result.at("data")) {
      bool matches = entry.value("clientUserMessageId", std::string()) ==
                     "factory-proof-" + d.at("id").get<std::string>();
      for (const auto &content : entry.at("input"))
        matches |= content.value("type", std::string()) == "text" &&
                   content.value("text", std::string()).find(marker) !=
                       std::string::npos;
      if (matches) {
        write_json(bundle / "delivery.json",
                   Json{{"status", "delivered"},
                        {"detail",
                         "Confirmed in the originating thread's pending queue"},
                        {"queued_submission_id", entry.at("id")}});
        return true;
      }
    }
    if (!result.contains("nextCursor") || result.at("nextCursor").is_null())
      break;
    queuedParams["cursor"] = result.at("nextCursor");
  }
  Json params{
      {"threadId", m.at("thread")}, {"limit", 50}, {"sortDirection", "desc"}};
  for (int page = 0; page < 5; ++page) {
    auto result = codex_rpc(endpoint, "thread/items/list", params);
    for (const auto &entry : result.at("data")) {
      const auto &item = entry.at("item");
      if (item.value("type", std::string()) != "userMessage")
        continue;
      for (const auto &content : item.at("content"))
        if (content.value("type", std::string()) == "text" &&
            content.value("text", std::string()).find(marker) !=
                std::string::npos) {
          write_json(bundle / "delivery.json",
                     Json{{"status", "delivered"},
                          {"detail", "Reconciled against the exact originating "
                                     "thread user message"},
                          {"item", item.at("id")}});
          return true;
        }
    }
    if (!result.contains("nextCursor") || result.at("nextCursor").is_null())
      break;
    params["cursor"] = result.at("nextCursor");
  }
  return false;
}
bool start_queued_feedback(const Json &config, const fs::path &bundle) {
  auto state = read_json(bundle / "delivery.json");
  if (!state.contains("queued_submission_id") || state.contains("turn_id"))
    return true;
  const auto thread = read_json(bundle / "manifest.json").at("thread");
  const auto socket = config.at("socket").get<std::string>();
  if (is_antigravity_endpoint(socket)) {
    try {
      const auto traj = antigravity_rpc(socket, "GetCascadeTrajectory",
                                        Json{{"cascadeId", thread}});
      const auto status =
          traj.value("status", std::string("CASCADE_RUN_STATUS_IDLE"));
      if (status == "CASCADE_RUN_STATUS_RUNNING" ||
          status == "CASCADE_RUN_STATUS_BUSY") {
        state["status"] = "delivered";
        state["detail"] =
            "Feedback queued for the originating agent's next turn";
        write_json(bundle / "delivery.json", state);
        return true;
      }
      antigravity_rpc(
          socket, "SendAllQueuedMessages",
          Json{{"cascadeId", thread},
               {"queuedSubmissionId", state.at("queued_submission_id")}});
      state["turn_id"] = "started-antigravity-turn";
      state["status"] = "delivered";
      state["detail"] = "Feedback started a user turn in the originating "
                        "Antigravity conversation";
      write_json(bundle / "delivery.json", state);
      return true;
    } catch (const std::exception &error) {
      const std::string detail = error.what();
      try {
        if (reconcile_delivery(config, bundle) &&
            read_json(bundle / "delivery.json").contains("item"))
          return true;
      } catch (const std::exception &) {
      }
      state["status"] = "queued";
      state["detail"] = "Feedback is saved in Antigravity's queue; starting "
                        "its turn needs a retry: " +
                        detail;
      write_json(bundle / "delivery.json", state);
      return false;
    }
  }
  try {
    const auto status =
        codex_rpc(socket, "thread/read", Json{{"threadId", thread}})
            .at("thread")
            .at("status")
            .at("type");
    // Preserve an active turn and leave its accepted input in the ordinary
    // queue. Explicitly wake an idle reviewer waiting for human feedback.
    if (status == "active") {
      state["status"] = "delivered";
      state["detail"] = "Feedback queued for the originating agent's next turn";
      write_json(bundle / "delivery.json", state);
      return true;
    }
    const auto started = codex_rpc(
        socket, "thread/queue/start",
        Json{{"threadId", thread},
             {"queuedSubmissionId", state.at("queued_submission_id")}});
    state["turn_id"] = started.at("turn").at("id");
    state["status"] = "delivered";
    state["detail"] = "Feedback started a user turn in the originating thread";
    write_json(bundle / "delivery.json", state);
    return true;
  } catch (const std::exception &error) {
    const std::string detail = error.what();
    try {
      if (reconcile_delivery(config, bundle) &&
          read_json(bundle / "delivery.json").contains("item"))
        return true;
    } catch (const std::exception &) {
    }
    // The message was already accepted. Retry may start it, never add it again.
    state["status"] = "queued";
    state["detail"] = "Feedback is saved in Codex's queue; starting its turn "
                      "needs a retry: " +
                      detail;
    write_json(bundle / "delivery.json", state);
    return false;
  }
}
} // namespace factory::proof
