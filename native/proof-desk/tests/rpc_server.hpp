#pragma once
#include "../proof.hpp"
#include <algorithm>
#include <cctype>
#include <csignal>
#include <cstring>
#include <netinet/in.h>
#include <openssl/evp.h>
#include <sstream>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

// Independent local WebSocket peer for protocol and goal lifecycle tests.
struct RpcFixture {
  pid_t pid = -1;
  explicit RpcFixture(const factory::proof::fs::path &path,
                      const factory::proof::fs::path &stateFile) {
    using namespace factory::proof;
    int listener = socket(AF_UNIX, SOCK_STREAM, 0);
    require(listener >= 0, "Fixture socket failed");
    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    require(path.string().size() < sizeof(addr.sun_path),
            "Fixture socket path too long");
    std::strcpy(addr.sun_path, path.c_str());
    require(path.string().front() == '@', "Fixture IPC must be abstract");
    addr.sun_path[0] = '\0';
    const auto addressLength =
        offsetof(sockaddr_un, sun_path) + path.string().size();
    require(bind(listener, reinterpret_cast<sockaddr *>(&addr),
                 addressLength) == 0 &&
                listen(listener, 8) == 0,
            "Fixture listen failed");
    pid = fork();
    require(pid >= 0, "Fixture fork failed");
    if (pid == 0) {
      signal(SIGPIPE, SIG_IGN);
      for (;;) {
        int fd = accept(listener, nullptr, nullptr);
        if (fd < 0)
          _exit(2);
        try {
          auto readBytes = [&](size_t count) {
            std::string out(count, '\0');
            size_t p = 0;
            while (p < count) {
              auto n = read(fd, out.data() + p, count - p);
              require(n > 0, "Fixture client closed");
              p += n;
            }
            return out;
          };
          auto writeBytes = [&](const std::string &bytes) {
            size_t p = 0;
            while (p < bytes.size()) {
              auto n = write(fd, bytes.data() + p, bytes.size() - p);
              require(n > 0, "Fixture write failed");
              p += n;
            }
          };
          std::string headers;
          while (headers.find("\r\n\r\n") == std::string::npos)
            headers += readBytes(1);
          auto start = headers.find("Sec-WebSocket-Key: ");
          require(start != std::string::npos, "Missing client key");
          start += 19;
          auto key = headers.substr(start, headers.find("\r\n", start) - start);
          auto challenge = key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
          unsigned char hash[64], encoded[128];
          unsigned size = 0;
          EVP_Digest(challenge.data(), challenge.size(), hash, &size,
                     EVP_sha1(), nullptr);
          EVP_EncodeBlock(encoded, hash, size);
          auto state = read_json(stateFile);
          writeBytes(
              "HTTP/1.1 101 Switching Protocols\r\nUpgrade: "
              "websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " +
              (state.value("bad_upgrade", false)
                   ? std::string("invalid")
                   : std::string(reinterpret_cast<char *>(encoded))) +
              "\r\n\r\n");
          auto sendFrame = [&](unsigned first, const std::string &body) {
            std::string packet(1, static_cast<char>(first));
            if (body.size() < 126)
              packet.push_back(static_cast<char>(body.size()));
            else if (body.size() < 65536) {
              packet.push_back(126);
              packet.push_back(static_cast<char>(body.size() >> 8));
              packet.push_back(static_cast<char>(body.size()));
            } else {
              packet.push_back(127);
              for (int shift = 56; shift >= 0; shift -= 8)
                packet.push_back(
                    static_cast<char>(uint64_t(body.size()) >> shift));
            }
            packet += body;
            writeBytes(packet);
          };
          for (;;) {
            auto head = readBytes(2);
            auto op = static_cast<unsigned char>(head[0]) & 15;
            auto len = static_cast<unsigned char>(head[1]) & 127;
            size_t length = len;
            require(head[1] & 0x80, "Client frames must be masked");
            if (len == 126) {
              auto b = readBytes(2);
              length = (static_cast<unsigned char>(b[0]) << 8) |
                       static_cast<unsigned char>(b[1]);
            }
            require(len != 127, "Fixture request too large");
            auto mask = readBytes(4), body = readBytes(length);
            for (size_t i = 0; i < length; ++i)
              body[i] ^= mask[i % 4];
            if (op == 10)
              continue;
            auto request = Json::parse(body);
            if (!request.contains("id"))
              continue;
            auto method = request.at("method").get<std::string>();
            state = read_json(stateFile);
            Json result = Json::object();
            if (method == "thread/goal/get")
              result["goal"] = state.at("goal");
            if (method == "thread/goal/set") {
              require(request.at("params").at("origin") == "user",
                      "Missing human authorization");
              require(!request.at("params").contains("objective") &&
                          !request.at("params").contains("tokenBudget"),
                      "Review reset goal accounting");
              state["goal"]["status"] = request.at("params").at("status");
              write_json(stateFile, state);
              result["goal"] = state.at("goal");
            }
            if (method == "thread/items/list")
              result =
                  Json{{"data", state.at("items")}, {"nextCursor", nullptr}};
            if (method == "thread/queue/list")
              result = Json{{"data", state.value("queue", Json::array())},
                            {"nextCursor", nullptr}};
            if (method == "thread/queue/list" && !result["data"].empty() &&
                state.contains("list_image_bytes"))
              result["data"][0]["input"].push_back(Json{
                  {"type", "image"},
                  {"url",
                   "data:image/png;base64," +
                       std::string(state.at("list_image_bytes").get<size_t>(),
                                   'A')}});
            if (method == "thread/read")
              result =
                  Json{{"thread",
                        {{"status",
                          {{"type", state.value("runtime_status", "idle")}}}}}};
            if (method == "thread/queue/start") {
              const auto requested =
                  request.at("params").at("queuedSubmissionId");
              auto queue = state.at("queue");
              bool found = false;
              for (size_t i = 0; i < queue.size(); ++i) {
                if (queue[i].at("id") != requested)
                  continue;
                state["items"].push_back(
                    Json{{"item",
                          {{"id", "started-user-item"},
                           {"type", "userMessage"},
                           {"content", queue[i].at("input")}}}});
                queue.erase(i);
                found = true;
                break;
              }
              require(found, "Fixture queued submission missing");
              state["queue"] = queue;
              state["start_calls"] = state.value("start_calls", 0) + 1;
              write_json(stateFile, state);
              result = Json{{"turn", {{"id", "started-review-turn"}}}};
            }
            if (method == "thread/queue/add") {
              state["queue_calls"] = state.value("queue_calls", 0) + 1;
              if (!state.value("queue_refuse", false)) {
                auto entry = request.at("params");
                entry["id"] =
                    "queued-" +
                    std::to_string(state.at("queue_calls").get<int>());
                if (!state.contains("queue"))
                  state["queue"] = Json::array();
                state["queue"].push_back(entry);
                result = Json{{"queuedSubmission", entry}};
                // The daemon resolves local images to data URLs in its queue
                // receipt. The client only needs the receipt identifiers.
                if (state.contains("receipt_image_bytes"))
                  result["queuedSubmission"]["input"].push_back(Json{
                      {"type", "image"},
                      {"url",
                       "data:image/png;base64," +
                           std::string(
                               state.at("receipt_image_bytes").get<size_t>(),
                               'A')}});
              }
              write_json(stateFile, state);
              if (state.value("drop_queue_reply", false))
                throw std::runtime_error(
                    "Fixture lost the reply after enqueue");
            }
            Json envelope{{"id", request.at("id")}, {"result", result}};
            if (method == "thread/queue/add" &&
                state.value("queue_refuse", false))
              envelope = Json{{"id", request.at("id")},
                              {"error",
                               {{"code", -32602},
                                {"message", "Fixture rejected queue input"}}}};
            auto response = envelope.dump();
            if (method == "thread/queue/add" &&
                state.value("oversized_reply", false)) {
              std::string packet{"\x81\x7f", 2};
              const uint64_t size = 64ULL * 1024 * 1024 + 1;
              for (int shift = 56; shift >= 0; shift -= 8)
                packet.push_back(static_cast<char>(size >> shift));
              writeBytes(packet);
              throw std::runtime_error(
                  "Oversized fixture header without payload");
            }
            sendFrame(0x89,
                      "ping"); // The client must answer this control frame.
            if (state.value("single_frame", false)) {
              sendFrame(0x81, response);
              continue;
            }
            auto split = response.size() / 2;
            sendFrame(1, response.substr(0, split));
            sendFrame(0x89, "interleaved ping");
            sendFrame(0x80, response.substr(split));
          }
        } catch (const std::exception &) {
        }
        close(fd);
      }
    }
    close(listener);
  }
  ~RpcFixture() {
    if (pid > 0) {
      kill(pid, SIGTERM);
      waitpid(pid, nullptr, 0);
    }
  }
};

// Independent local Connect/HTTP peer for Antigravity LanguageServerService
// contract tests.
struct AntigravityRpcFixture {
  pid_t pid = -1;
  uint16_t port = 0;
  explicit AntigravityRpcFixture(const factory::proof::fs::path &stateFile) {
    using namespace factory::proof;
    int listener = socket(AF_INET, SOCK_STREAM, 0);
    require(listener >= 0, "Antigravity fixture socket failed");
    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = 0;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    socklen_t addrLen = sizeof(addr);
    require(bind(listener, reinterpret_cast<sockaddr *>(&addr), addrLen) == 0 &&
                getsockname(listener, reinterpret_cast<sockaddr *>(&addr),
                            &addrLen) == 0 &&
                listen(listener, 8) == 0,
            "Antigravity fixture listen failed");
    port = ntohs(addr.sin_port);
    pid = fork();
    require(pid >= 0, "Antigravity fixture fork failed");
    if (pid == 0) {
      signal(SIGPIPE, SIG_IGN);
      for (;;) {
        int fd = accept(listener, nullptr, nullptr);
        if (fd < 0)
          _exit(2);
        try {
          auto readBytes = [&](size_t count) {
            std::string out(count, '\0');
            size_t p = 0;
            while (p < count) {
              auto n = read(fd, out.data() + p, count - p);
              require(n > 0, "Antigravity fixture client closed");
              p += n;
            }
            return out;
          };
          auto writeBytes = [&](const std::string &bytes) {
            size_t p = 0;
            while (p < bytes.size()) {
              auto n = write(fd, bytes.data() + p, bytes.size() - p);
              require(n > 0, "Antigravity fixture write failed");
              p += n;
            }
          };
          std::string headers;
          while (headers.find("\r\n\r\n") == std::string::npos)
            headers += readBytes(1);
          const auto lineEnd = headers.find("\r\n");
          std::istringstream reqLine(headers.substr(0, lineEnd));
          std::string httpMethod, target;
          reqLine >> httpMethod >> target;
          const std::string prefix =
              "/exa.language_server_pb.LanguageServerService/";
          require(httpMethod == "POST" && target.rfind(prefix, 0) == 0,
                  "Unexpected Antigravity request line");
          const auto method = target.substr(prefix.size());
          auto header = [&](const std::string &name) {
            size_t start = lineEnd + 2;
            std::string found;
            while (start < headers.size() - 2) {
              auto end = headers.find("\r\n", start),
                   sep = headers.find(':', start);
              auto key = headers.substr(start, sep - start);
              std::transform(key.begin(), key.end(), key.begin(),
                             [](unsigned char c) { return std::tolower(c); });
              if (key == name) {
                auto vStart = headers.find_first_not_of(" \t", sep + 1);
                auto vEnd = headers.find_last_not_of(" \t", end - 1);
                if (vStart < end)
                  found = headers.substr(vStart, vEnd - vStart + 1);
              }
              start = end + 2;
            }
            return found;
          };
          const auto lenStr = header("content-length");
          const size_t bodyLen = lenStr.empty() ? 0 : std::stoul(lenStr);
          const auto body = bodyLen > 0 ? readBytes(bodyLen) : std::string();
          auto state = read_json(stateFile);
          auto sendHttp = [&](int status, const std::string &reason,
                              const std::string &payload, bool chunked = false) {
            std::ostringstream out;
            out << "HTTP/1.1 " << status << ' ' << reason
                << "\r\nContent-Type: application/json\r\n";
            if (chunked) {
              const auto split = payload.size() / 2;
              const auto first = payload.substr(0, split);
              const auto second = payload.substr(split);
              out << "Transfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
                  << std::hex << first.size() << "\r\n"
                  << first << "\r\n"
                  << second.size() << "\r\n"
                  << second << "\r\n0\r\n\r\n";
            } else {
              out << "Content-Length: " << payload.size()
                  << "\r\nConnection: close\r\n\r\n"
                  << payload;
            }
            writeBytes(out.str());
          };
          if (header("x-codeium-csrf-token") !=
              state.value("csrf_token", std::string("fixture-csrf"))) {
            sendHttp(403, "Forbidden",
                     Json{{"code", "permission_denied"},
                          {"message", "Fixture rejected CSRF token"}}
                         .dump());
            close(fd);
            continue;
          }
          const auto request =
              body.empty() ? Json::object() : Json::parse(body);
          if (method == "GetCascadeTrajectory") {
            Json result{
                {"status",
                 state.value("status", std::string("CASCADE_RUN_STATUS_IDLE"))},
                {"trajectory",
                 {{"cascadeId", request.at("cascadeId")},
                  {"steps", state.value("steps", Json::array())}}},
                {"queuedSteps", state.value("queued_steps", Json::array())}};
            sendHttp(200, "OK", result.dump(),
                     state.value("chunked_reply", false));
          } else if (method == "SendUserCascadeMessage") {
            state["send_calls"] = state.value("send_calls", 0) + 1;
            if (state.value("send_refuse", false)) {
              write_json(stateFile, state);
              sendHttp(400, "Bad Request",
                       Json{{"code", "invalid_argument"},
                            {"message", "Fixture rejected cascade message"}}
                           .dump());
              close(fd);
              continue;
            }
            if (state.value("oversized_reply", false)) {
              write_json(stateFile, state);
              writeBytes("HTTP/1.1 200 OK\r\nContent-Type: "
                         "application/json\r\nContent-Length: "
                         "67108865\r\nConnection: close\r\n\r\n");
              close(fd);
              continue;
            }
            Json step{
                {"type", "CORTEX_STEP_TYPE_USER_INPUT"},
                {"status", "CORTEX_STEP_STATUS_DONE"},
                {"metadata",
                 {{"executionId",
                   "agy-step-" +
                       std::to_string(state.at("send_calls").get<int>())}}},
                {"userInput",
                 {{"items", request.at("items")},
                  {"media", request.value("media", Json::array())},
                  {"userConfig", request.value("cascadeConfig", Json())},
                  {"userAgentSpec", request.value("customAgentSpec", Json())},
                  {"deliveryStrategy",
                   request.value("deliveryStrategy", std::string())}}}};
            if (!state.contains("steps"))
              state["steps"] = Json::array();
            state["steps"].push_back(step);
            write_json(stateFile, state);
            if (state.value("drop_send_reply", false))
              throw std::runtime_error("Fixture dropped reply after send");
            sendHttp(200, "OK", "{}");
          } else if (method == "SendAllQueuedMessages") {
            auto queued = state.value("queued_steps", Json::array());
            require(!queued.empty(), "No queued Antigravity steps to start");
            for (const auto &step : queued)
              state["steps"].push_back(step);
            state["queued_steps"] = Json::array();
            state["start_calls"] = state.value("start_calls", 0) + 1;
            write_json(stateFile, state);
            sendHttp(200, "OK", "{}");
          } else {
            sendHttp(404, "Not Found",
                     Json{{"code", "unimplemented"},
                          {"message", "Unknown method"}}
                         .dump());
          }
        } catch (const std::exception &) {
        }
        close(fd);
      }
    }
    close(listener);
  }
  std::string endpoint(const std::string &csrf = "fixture-csrf") const {
    return "http://127.0.0.1:" + std::to_string(port) + "#" + csrf;
  }
  ~AntigravityRpcFixture() {
    if (pid > 0) {
      kill(pid, SIGTERM);
      waitpid(pid, nullptr, 0);
    }
  }
};
