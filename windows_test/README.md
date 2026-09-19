# Windows test desktop through KasmVNC

This workflow starts a temporary Windows Server 2025 x64 desktop for manual
development and testing of this repository. It does not install Kasm Workspaces
or noVNC. Codespaces runs an RDP client inside a dedicated KasmVNC display.

Connection: browser → Codespaces KasmVNC → FreeRDP → authenticated TLS tunnel
→ Windows RDP. The Windows account requires NLA. The tunnel only forwards to
loopback port 3389, and its random access path changes with every run.

The `windows-connection-RUN_ID` artifact is encrypted with RSA-OAEP-SHA256.
Its private key is kept only in `.windows-test/session-private.pem` in the
original Codespaces workspace. Never commit the private key or credentials.
Replacing the public key requires keeping the corresponding private key.

The first push to `windows_test_1` starts a 120-minute session. Later sessions
can be manually dispatched with 15–330 minutes. There is no automatic renewal.
Cancel the Actions run to end testing. Windows state is ephemeral; save project
changes before the session ends. The checked-out repository is copied to the
public Windows desktop, without persisted GitHub checkout credentials.

This is Windows Server 2025, not Windows 11. KasmVNC forwards the Linux display
containing the Windows RDP client; it is not installed on Windows.
