import Foundation

struct MockDetailData {
    static func containerInspect(name: String) -> String {
        """
        {
          "Id": "abc123def456789012345678901234567890abcdef1234567890abcdef123456",
          "Created": "2026-04-27T08:30:00.123456789Z",
          "Path": "/docker-entrypoint.sh",
          "Args": ["nginx", "-g", "daemon off;"],
          "State": {
            "Status": "running",
            "Running": true,
            "Paused": false,
            "Restarting": false,
            "OOMKilled": false,
            "Dead": false,
            "Pid": 4821,
            "ExitCode": 0,
            "StartedAt": "2026-04-27T08:30:01.456789012Z",
            "FinishedAt": "0001-01-01T00:00:00Z"
          },
          "Image": "sha256:aaa111bbb222ccc333ddd444eee555fff666aaa111bbb222ccc333ddd444eee5",
          "Name": "/\(name)",
          "RestartCount": 0,
          "Platform": "linux",
          "NetworkSettings": {
            "IPAddress": "172.17.0.2",
            "IPPrefixLen": 16,
            "Gateway": "172.17.0.1",
            "MacAddress": "02:42:ac:11:00:02",
            "Ports": {
              "80/tcp": [{"HostIp": "0.0.0.0", "HostPort": "8080"}]
            },
            "Networks": {
              "bridge": {
                "IPAddress": "172.17.0.2",
                "Gateway": "172.17.0.1",
                "NetworkID": "net001abc"
              }
            }
          },
          "Mounts": [
            {
              "Type": "volume",
              "Name": "app_data",
              "Source": "/var/lib/docker/volumes/app_data/_data",
              "Destination": "/usr/share/nginx/html",
              "Mode": "rw",
              "RW": true
            }
          ],
          "Config": {
            "Hostname": "\(name)",
            "Env": ["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", "NGINX_VERSION=1.25.4"],
            "Cmd": ["nginx", "-g", "daemon off;"],
            "Image": "nginx:latest",
            "WorkingDir": "",
            "Labels": {"maintainer": "NGINX Docker Maintainers"}
          },
          "HostConfig": {
            "Binds": ["/host/data:/container/data:rw"],
            "Memory": 536870912,
            "CpuShares": 1024,
            "RestartPolicy": {"Name": "unless-stopped", "MaximumRetryCount": 0},
            "LogConfig": {"Type": "json-file", "Config": {"max-size": "10m", "max-file": "3"}}
          }
        }
        """
    }

    static func containerLogs(name: String) -> [String] {
        [
            "2026-04-27T10:00:00.100Z stdout: /docker-entrypoint.sh: /docker-entrypoint.d/ is not empty, will attempt to perform configuration",
            "2026-04-27T10:00:00.200Z stdout: /docker-entrypoint.sh: Looking for shell scripts in /docker-entrypoint.d/",
            "2026-04-27T10:00:00.300Z stdout: /docker-entrypoint.sh: Launching /docker-entrypoint.d/10-listen-on-ipv6-by-default.sh",
            "2026-04-27T10:00:00.400Z stdout: 10-listen-on-ipv6-by-default.sh: info: Getting the checksum of /etc/nginx/conf.d/default.conf",
            "2026-04-27T10:00:00.500Z stdout: 10-listen-on-ipv6-by-default.sh: info: Enabled listen on IPv6 in /etc/nginx/conf.d/default.conf",
            "2026-04-27T10:00:00.600Z stdout: /docker-entrypoint.sh: Sourcing /docker-entrypoint.d/15-local-resolvers.envsh",
            "2026-04-27T10:00:00.700Z stdout: /docker-entrypoint.sh: Launching /docker-entrypoint.d/20-envsubst-on-templates.sh",
            "2026-04-27T10:00:00.800Z stdout: /docker-entrypoint.sh: Launching /docker-entrypoint.d/30-tune-worker-processes.sh",
            "2026-04-27T10:00:01.000Z stdout: /docker-entrypoint.sh: Configuration complete; ready for start up",
            "2026-04-27T10:00:01.100Z stdout: nginx: [notice] using the \"epoll\" event method",
            "2026-04-27T10:00:01.123Z stdout: nginx: [notice] start worker process 31",
            "2026-04-27T10:00:01.124Z stdout: nginx: [notice] start worker process 32",
            "2026-04-27T10:00:05.200Z stdout: 172.17.0.1 - - [27/Apr/2026:10:00:05 +0000] \"GET / HTTP/1.1\" 200 615 \"-\" \"curl/8.5.0\"",
            "2026-04-27T10:00:05.201Z stdout: 172.17.0.1 - - [27/Apr/2026:10:00:05 +0000] \"GET /favicon.ico HTTP/1.1\" 404 153 \"-\" \"Mozilla/5.0\"",
            "2026-04-27T10:00:10.300Z stderr: 2026/04/27 10:00:10 [error] 31#31: *2 open() \"/usr/share/nginx/html/missing\" failed (2: No such file or directory)",
            "2026-04-27T10:00:10.301Z stdout: 172.17.0.1 - - [27/Apr/2026:10:00:10 +0000] \"GET /missing HTTP/1.1\" 404 153 \"-\" \"curl/8.5.0\"",
            "2026-04-27T10:01:00.000Z stdout: 172.17.0.1 - - [27/Apr/2026:10:01:00 +0000] \"GET /api/health HTTP/1.1\" 200 2 \"-\" \"kube-probe/1.29\"",
            "2026-04-27T10:02:00.000Z stdout: 172.17.0.1 - - [27/Apr/2026:10:02:00 +0000] \"GET /api/health HTTP/1.1\" 200 2 \"-\" \"kube-probe/1.29\"",
            "2026-04-27T10:03:00.000Z stdout: 172.17.0.1 - - [27/Apr/2026:10:03:00 +0000] \"POST /api/data HTTP/1.1\" 201 48 \"-\" \"python-requests/2.31.0\"",
            "2026-04-27T10:03:15.500Z stderr: 2026/04/27 10:03:15 [warn] 32#32: *8 upstream timed out (110: Connection timed out)",
            "2026-04-27T10:04:00.000Z stdout: 172.17.0.1 - - [27/Apr/2026:10:04:00 +0000] \"GET /api/health HTTP/1.1\" 200 2 \"-\" \"kube-probe/1.29\"",
        ]
    }

    static func containerTop(name: String) -> [(pid: String, user: String, cpu: String, mem: String, command: String)] {
        [
            (pid: "4821", user: "root", cpu: "0.1%", mem: "0.3%", command: "nginx: master process nginx -g daemon off;"),
            (pid: "4850", user: "nginx", cpu: "0.0%", mem: "0.2%", command: "nginx: worker process"),
            (pid: "4851", user: "nginx", cpu: "0.0%", mem: "0.2%", command: "nginx: worker process"),
            (pid: "4852", user: "nginx", cpu: "0.0%", mem: "0.1%", command: "nginx: cache manager process"),
        ]
    }

    static func containerStats(name: String) -> (cpu: String, memory: String, memLimit: String, netIO: String, blockIO: String, pids: Int) {
        (cpu: "0.15%", memory: "24.5MiB", memLimit: "512MiB", netIO: "1.2kB / 648B", blockIO: "8.19kB / 0B", pids: 4)
    }

    static func containerChanges(name: String) -> [(kind: String, path: String)] {
        [
            (kind: "Modified", path: "/etc/nginx/conf.d/default.conf"),
            (kind: "Added", path: "/var/log/nginx/access.log"),
            (kind: "Added", path: "/var/log/nginx/error.log"),
            (kind: "Modified", path: "/run/nginx.pid"),
            (kind: "Added", path: "/tmp/nginx-proxy-cache"),
            (kind: "Deleted", path: "/docker-entrypoint.d/.placeholder"),
        ]
    }

    static func imageInspect(repo: String) -> String {
        """
        {
          "Id": "sha256:aaa111bbb222ccc333ddd444eee555fff666aaa111bbb222ccc333ddd444eee5",
          "RepoTags": ["\(repo):latest"],
          "RepoDigests": ["\(repo)@sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"],
          "Created": "2026-04-15T12:00:00.000000000Z",
          "Architecture": "arm64",
          "Os": "linux",
          "Size": 187654321,
          "RootFS": {
            "Type": "layers",
            "Layers": [
              "sha256:layer1aaa111bbb222ccc333ddd444eee555fff666",
              "sha256:layer2aaa111bbb222ccc333ddd444eee555fff666",
              "sha256:layer3aaa111bbb222ccc333ddd444eee555fff666"
            ]
          },
          "Config": {
            "Env": ["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"],
            "Cmd": ["bash"],
            "ExposedPorts": {"80/tcp": {}},
            "Labels": {"maintainer": "maintainer@example.com"}
          }
        }
        """
    }

    static func imageHistory(repo: String) -> [(id: String, created: String, size: String, command: String)] {
        [
            (id: "sha256:aaa111", created: "2 weeks ago", size: "0B", command: "CMD [\"nginx\" \"-g\" \"daemon off;\"]"),
            (id: "sha256:bbb222", created: "2 weeks ago", size: "1.4kB", command: "EXPOSE map[80/tcp:{}]"),
            (id: "sha256:ccc333", created: "2 weeks ago", size: "61.1MB", command: "RUN /bin/sh -c set -x && apt-get update && apt-get install --no-install-recommends -y nginx"),
            (id: "sha256:ddd444", created: "2 weeks ago", size: "4.1kB", command: "COPY docker-entrypoint.sh / # buildkit"),
            (id: "sha256:eee555", created: "3 weeks ago", size: "77.8MB", command: "/bin/sh -c #(nop) ADD file:abc123 in /"),
            (id: "<missing>", created: "3 weeks ago", size: "0B", command: "/bin/sh -c #(nop) ENV DEBIAN_FRONTEND=noninteractive"),
        ]
    }

    static func volumeInspect(name: String) -> String {
        """
        {
          "CreatedAt": "2026-04-20T14:30:00Z",
          "Driver": "local",
          "Labels": null,
          "Mountpoint": "/var/lib/docker/volumes/\(name)/_data",
          "Name": "\(name)",
          "Options": null,
          "Scope": "local",
          "Status": {"size": "256MB"}
        }
        """
    }

    static func networkInspect(name: String) -> String {
        """
        {
          "Name": "\(name)",
          "Id": "net001abc123def456789012345678901234567890abcdef1234567890",
          "Created": "2026-04-25T09:00:00.000000000Z",
          "Scope": "local",
          "Driver": "bridge",
          "EnableIPv6": false,
          "IPAM": {
            "Driver": "default",
            "Config": [{"Subnet": "172.18.0.0/16", "Gateway": "172.18.0.1"}]
          },
          "Containers": {
            "abc123": {"Name": "web-server", "IPv4Address": "172.18.0.2/16"},
            "def456": {"Name": "api-service", "IPv4Address": "172.18.0.3/16"}
          },
          "Options": {},
          "Labels": {}
        }
        """
    }

    static func sshConfig(profile: String) -> String {
        """
        Host colima
          HostName 127.0.0.1
          User user
          Port 60022
          StrictHostKeyChecking no
          UserKnownHostsFile /dev/null
          IdentityFile ~/.colima/_lima/_config/user
          IdentitiesOnly yes
          LogLevel ERROR
        """
    }

    static func searchResults(term: String) -> [(name: String, description: String, stars: Int, official: Bool)] {
        [
            (name: term, description: "Official \(term) image", stars: 18500, official: true),
            (name: "\(term)-alpine", description: "Lightweight Alpine-based \(term)", stars: 4200, official: false),
            (name: "bitnami/\(term)", description: "Bitnami \(term) Docker Image", stars: 1100, official: false),
            (name: "linuxserver/\(term)", description: "LinuxServer.io \(term) image", stars: 890, official: false),
            (name: "\(term)-slim", description: "Minimal \(term) image", stars: 320, official: false),
        ]
    }

    static func commandOutput(tool: String, args: String) -> String {
        switch args.components(separatedBy: " ").first ?? "" {
        case "ps":
            return "CONTAINER ID   IMAGE          STATUS          NAMES\nabc123def456   nginx:latest   Up 2 hours      web-server\ndef456ghi789   postgres:16    Up 2 hours      postgres-db"
        case "images":
            return "REPOSITORY   TAG       IMAGE ID       SIZE\nnginx        latest    sha256:aaa111  187MB\npostgres     16        sha256:bbb222  432MB"
        case "list", "ls":
            return tool == "incus" ? "+----------+---------+---------------------+------+\n|   NAME   |  STATE  |       IPV4          | TYPE |\n+----------+---------+---------------------+------+\n| default  | RUNNING | 192.168.64.2 (eth0) | VM   |\n+----------+---------+---------------------+------+" : "CONTAINER ID   IMAGE          STATUS\nabc123def456   nginx:latest   Up 2 hours"
        case "info":
            return "Client:\n Context: colima\n Version: 24.0.7\nServer:\n Containers: 5\n  Running: 3\n  Paused: 1\n  Stopped: 1\n Images: 5"
        default:
            return "\(tool): command executed successfully"
        }
    }
}
