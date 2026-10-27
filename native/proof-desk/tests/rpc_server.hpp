#pragma once
#include "../proof.hpp"
#include <csignal>
#include <cstring>
#include <openssl/evp.h>
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
            else {
              packet.push_back(126);
              packet.push_back(static_cast<char>(body.size() >> 8));
              packet.push_back(static_cast<char>(body.size()));
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
            sendFrame(0x89,
                      "ping"); // The client must answer this control frame.
            auto split = response.size() / 2;
            sendFrame(1, response.substr(0, split));
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
