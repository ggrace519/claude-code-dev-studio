# Typed, allowlisted IPC channel skeleton

Electron-flavored TypeScript; the pattern (shared contract → minimal preload
verbs → main-side sender check + runtime parse + opaque-ID resolution) maps
directly onto Tauri commands and any custom pipe protocol.

```ts
// shared/ipc-contract.ts — one module, imported by preload AND main.
import { z } from "zod";

export const contract = {
  "doc:read": {
    // Renderer sends an opaque id it was previously handed — NEVER a path.
    request: z.object({ docId: z.string().uuid() }),
    response: z.object({ title: z.string(), body: z.string() }),
  },
  "doc:export": {
    request: z.object({ docId: z.string().uuid(), format: z.enum(["pdf", "md"]) }),
    response: z.object({ ok: z.literal(true) }),
  },
} as const;
```

```ts
// preload.ts — expose verbs, never ipcRenderer itself and never a
// generic invoke(channel, ...) passthrough (that deletes the allowlist).
import { contextBridge, ipcRenderer } from "electron";

contextBridge.exposeInMainWorld("api", {
  readDoc:   (docId: string)                 => ipcRenderer.invoke("doc:read",   { docId }),
  exportDoc: (docId: string, format: string) => ipcRenderer.invoke("doc:export", { docId, format }),
});
```

```ts
// main/ipc.ts
import { ipcMain } from "electron";
import { contract } from "../shared/ipc-contract";

function assertTrustedSender(event: Electron.IpcMainInvokeEvent) {
  // 1. Sender check — the payload can't tell you who is calling.
  //    Compare against the URLs you actually load, not a substring match.
  const url = new URL(event.senderFrame.url);
  if (url.protocol !== "app:") throw new Error("forbidden sender");
}

ipcMain.handle("doc:read", async (event, payload) => {
  assertTrustedSender(event);

  // 2. Parse, don't trust — compile-time types don't survive a
  //    compromised renderer; zod runs at runtime.
  const req = contract["doc:read"].request.parse(payload);

  // 3. Resolve the opaque id to a real path on the MAIN side. The renderer
  //    never supplies paths, so there is no traversal surface here.
  const path = docRegistry.pathFor(req.docId); // throws if unknown
  const body = await fs.readFile(path, "utf8");

  return contract["doc:read"].response.parse({ title: docRegistry.titleFor(req.docId), body });
});
```

Large payloads: don't return multi-megabyte bodies through `invoke` — structured
clone copies them. Hand the renderer a `MessagePort` (`MessageChannelMain`) or
write to a temp file and return its opaque id.

## Review checklist for any new channel

- [ ] Contract entry added in the shared module; both sides import it
- [ ] Handler calls the sender check before touching the payload
- [ ] `request.parse()` runs before any side effect; parse failure returns an error, logs the channel + sender, and nothing else
- [ ] No renderer-supplied path, URL, or shell-command fragment is used directly
- [ ] Response is also schema-shaped — no leaking extra fields from internal objects
- [ ] A test sends a malformed payload and a forbidden-sender call and asserts both are rejected with no side effects
