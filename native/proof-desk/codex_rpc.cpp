#include "codex_rpc.hpp"
#include <algorithm>
#include <cctype>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <openssl/evp.h>
#include <openssl/rand.h>
#include <poll.h>
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
    require(received + count <= 8 * 1024 * 1024,
            "Codex response exceeds 8 MiB");
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
      require(length <= 8 * 1024 * 1024, "Oversized server WebSocket frame");
      if (op >= 8)
        require(fin && length <= 125, "Invalid WebSocket control frame");
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
      require(message.size() <= 8 * 1024 * 1024, "Oversized Codex message");
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
    throw RpcFailure(error.what(), sent);
  }
}
Json pause_for_review(const Json &config, const std::string &thread) {
  fs::path socket(config.at("socket").get<std::string>());
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
  Json queuedParams{{"threadId", m.at("thread")}, {"limit", 100}};
  for (int page = 0; page < 5; ++page) {
    auto result = codex_rpc(config.at("socket").get<std::string>(),
                            "thread/queue/list", queuedParams);
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
    auto result = codex_rpc(config.at("socket").get<std::string>(),
                            "thread/items/list", params);
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
