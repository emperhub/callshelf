import { spawn } from "node:child_process"
import fs from "node:fs"
import path from "node:path"
import { createEffect, createSignal } from "solid-js"
import {
  Command,
  MenuItem,
  Panel,
  Plugin,
  Style,
  TitlebarItem,
  type PanelTab,
} from "@opencode/plugin/gui"
import { RotateControl } from "./contract"
import css from "./panel.css?inline"

const LOG_LIMIT = 12000

type Status = {
  ip: string | null
  mode: string | null
  running: boolean
  exitCode: number | null
  log: string
}

function parseJson(text: string): any {
  const lines = text.split(/\r?\n/).map((line) => line.trim())
  for (let i = lines.length - 1; i >= 0; i--) {
    if (!lines[i].startsWith("{")) continue
    try {
      return JSON.parse(lines[i])
    } catch {
      /* keep looking */
    }
  }
  return null
}

export default Plugin.define({
  i18n: {
    en: {
      "panel.title": "Connection",
      "panel.rotate": "NEW IP",
      "panel.rotating": "CHANGING...",
      "panel.refresh": "CHECK",
      "panel.state": "EGRESS",
      "panel.ready": "READY",
      "panel.busy": "WORKING",
      "panel.hint": "Changes the public IP of this machine through Cloudflare WARP. Your LAN, router, and other apps are untouched.",
      "panel.empty": "no address yet",
      "titlebar.label": "NEW IP",
      "titlebar.busy": "IP...",
      "command.open": "Open the connection panel",
      "command.rotate": "Change the IP now",
      "toast.rotating": "Changing IP",
      "toast.done": "IP changed",
      "toast.failed": "IP did not change",
      "toast.failed.desc": "WARP kept the same address or the tunnel is not answering.",
    },
    th: {
      "panel.title": "การเชื่อมต่อ",
      "panel.rotate": "เปลี่ยน IP",
      "panel.rotating": "กำลังเปลี่ยน...",
      "panel.refresh": "ตรวจสอบ",
      "panel.state": "IP ขาออก",
      "panel.ready": "พร้อม",
      "panel.busy": "กำลังทำงาน",
      "panel.hint": "เปลี่ยน IP สาธารณะของเครื่องนี้ผ่าน Cloudflare WARP ไม่แตะเราเตอร์ วง LAN หรือแอพอื่นบนเครื่อง",
      "panel.empty": "ยังไม่มี IP",
      "titlebar.label": "เปลี่ยน IP",
      "titlebar.busy": "IP...",
      "command.open": "เปิดแผงการเชื่อมต่อ",
      "command.rotate": "เปลี่ยน IP ตอนนี้",
      "toast.rotating": "กำลังเปลี่ยน IP",
      "toast.done": "เปลี่ยน IP แล้ว",
      "toast.failed": "IP ยังเดิม",
      "toast.failed.desc": "WARP คืน IP เดิมหรือ tunnel ไม่ตอบ",
    },
  },

  main(ctx) {
    const home = process.env.USERPROFILE ?? process.env.HOME ?? ""
    const candidates = [
      process.env.CALLSHELF_SCRIPT,
      path.join(__dirname, "rotate.ps1"),
      path.join(home, "callshelf", "rotate.ps1"),
      path.join(home, "ip-rotate", "rotate.ps1"),
    ].filter(Boolean) as string[]

    const script = candidates.find((p) => fs.existsSync(p)) ?? candidates[0] ?? ""

    let running = false
    let probing = false
    let probed = false
    let exitCode: number | null = null
    let ip: string | null = null
    let mode: string | null = null
    let log = ""

    const append = (text: string) => {
      log = (log + text).slice(-LOG_LIMIT)
    }

    const exec = (args: string[], done: (out: string, code: number | null) => void) => {
      if (!script || !fs.existsSync(script)) {
        done(`{"ok":false,"error":"rotate.ps1 not found"}`, 1)
        return null
      }
      const proc = spawn(
        "powershell.exe",
        ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, ...args],
        { windowsHide: true },
      )
      let buffer = ""
      const take = (chunk: Buffer) => {
        buffer = (buffer + chunk.toString()).slice(-20000)
      }
      proc.stdout?.on("data", take)
      proc.stderr?.on("data", take)
      proc.on("error", (error) => append(`\n${error.message}`))
      proc.on("close", (code) => done(buffer, code))
      return proc
    }

    const probe = () => {
      if (probing) return false
      probing = true
      exec(["-Json"], (out, code) => {
        probing = false
        probed = true
        exitCode = code
        const data = parseJson(out)
        if (data?.ok) {
          ip = typeof data.ip === "string" ? data.ip : null
          mode = typeof data.mode === "string" ? data.mode : null
        } else {
          ip = null
          mode = null
          append(`\n${(data?.error as string) ?? out.trim()}`)
        }
      })
      return true
    }

    const rotate = () => {
      if (running) return false
      running = true
      exitCode = null
      append(`\n${new Date().toLocaleTimeString()}  rotate`)
      exec(["-Rotate", "-Json"], (out, code) => {
        running = false
        probed = true
        exitCode = code
        const data = parseJson(out)
        if (data?.after) ip = data.after
        if (code === 0) {
          append(`\n  ${data?.before ?? "?"} -> ${data?.after ?? "?"}  (${data?.method ?? "?"}, ${data?.elapsedSec ?? "?"}s)`)
        } else {
          append(`\n  ${(data?.error as string) ?? "no change"}`)
        }
      })
      return true
    }

    ctx.provide(RotateControl, {
      status: async () => {
        if (!probed && !probing && !running) probe()
        return { ip, mode, running, exitCode, log: log.slice(-LOG_LIMIT) }
      },
      refresh: async () => ({ started: probe() }),
      rotate: async () => ({ started: rotate() }),
    })

    ctx.onCleanup(() => {
      /* child processes exit on their own */
    })
  },

  setup(ctx) {
    const ipc = ctx.main(RotateControl)
    const [status, setStatus] = createSignal<Status | null>(null)
    let loading: { dismiss(): void } | null = null

    const poll = () => {
      void ipc
        .status()
        .then((next) => setStatus(next as Status))
        .catch(() => setStatus(null))
    }

    poll()
    const timer = setInterval(poll, 1000)

    const rotate = async () => {
      if (status()?.running) return
      const result = await ipc.rotate().catch(() => ({ started: false }))
      if (!result.started) return
      loading?.dismiss()
      loading = ctx.toast.show({ variant: "loading", title: ctx.t("toast.rotating"), persistent: true })
      poll()
    }

    const refresh = async () => {
      await ipc.refresh().catch(() => ({ started: false }))
      poll()
    }

    createEffect(() => {
      const current = status()
      if (!current || current.running || !loading) return
      loading.dismiss()
      loading = null
      if (current.exitCode === 0) {
        ctx.toast.show({ variant: "success", title: ctx.t("toast.done") })
      } else {
        ctx.toast.show({
          variant: "error",
          title: ctx.t("toast.failed"),
          description: ctx.t("toast.failed.desc"),
        })
      }
      poll()
    })

    ctx.add(TitlebarItem, (): TitlebarItem => {
      const current = status()
      return {
        id: "rotate",
        label: current?.running ? ctx.t("titlebar.busy") : ctx.t("titlebar.label"),
        title: ctx.t("titlebar.label"),
        icon: "globe",
        busy: !!current?.running,
        run: () => void rotate(),
      }
    })

    const openPanel = () => {
      const session = ctx.sessions.current()
      if (session) ctx.layout.open(`${ctx.id}:main`, session)
    }

    ctx.add(Command, () => ({
      id: "open",
      title: ctx.t("command.open"),
      group: ctx.t("panel.title"),
      bind: "mod+shift+i",
      run: openPanel,
    }))

    ctx.add(Command, () => ({
      id: "rotate",
      title: ctx.t("command.rotate"),
      group: ctx.t("panel.title"),
      run: () => void rotate(),
    }))

    ctx.add(MenuItem, (): MenuItem => {
      const session = ctx.sessions.current()
      return {
        menu: "session.panel",
        id: "open",
        title: ctx.t("panel.title"),
        opened: !!session && ctx.layout.state(`${ctx.id}:main`, session) !== "closed",
        run: openPanel,
      }
    })

    const tab: PanelTab = {
      id: "main",
      get title() {
        return ctx.t("panel.title")
      },
      closable: "compact",
      fallback: true,
    }

    const ui = ctx.ui

    const IpPanel = () => {
      const current = () => status()
      const running = () => !!current()?.running
      const address = () => current()?.ip ?? null
      const mode = () => current()?.mode ?? ""

      return (
        <div class="ipr">
          <div>
            <div class="ipr-head">
              <span class="ipr-label">{ctx.t("panel.state")}</span>
              <span class="ipr-state">
                <span class="ipr-dot" data-busy={running() ? "true" : "false"} />
                {running() ? ctx.t("panel.busy") : ctx.t("panel.ready")}
              </span>
            </div>
            <div class="ipr-ip" data-empty={address() ? "false" : "true"}>
              {address() ?? ctx.t("panel.empty")}
            </div>
            <div class="ipr-mode">{mode() === "warp-proxy" ? "WARP proxy" : mode() === "full-tunnel" ? "WARP tunnel" : ""}</div>
          </div>

          <ui.Button variant="contrast" busy={running()} disabled={running()} onClick={() => void rotate()}>
            {running() ? ctx.t("panel.rotating") : ctx.t("panel.rotate")}
          </ui.Button>

          <div class="ipr-row">
            <ui.Button variant="ghost" onClick={() => void refresh()}>
              {ctx.t("panel.refresh")}
            </ui.Button>
          </div>

          <div class="ipr-hint">{ctx.t("panel.hint")}</div>

          <div class="ipr-log" data-empty={current()?.log ? "false" : "true"}>
            {current()?.log?.trim() || "—"}
          </div>
        </div>
      )
    }

    ctx.add(Style, css)

    ctx.add(Panel, {
      id: "main",
      region: "side",
      width: "narrow",
      list: (input) => (input.open.includes("main") ? [tab] : []),
      render: () => <IpPanel />,
    })

    return () => clearInterval(timer)
  },
})
