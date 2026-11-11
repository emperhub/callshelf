import { Schema } from "effect"
import { Ipc } from "@opencode/plugin/gui"

export const RotateControl = Ipc.define({
  id: "callshelf.control",
  methods: {
    status: {
      output: Schema.Struct({
        ip: Schema.NullOr(Schema.String),
        mode: Schema.NullOr(Schema.String),
        running: Schema.Boolean,
        exitCode: Schema.NullOr(Schema.Number),
        log: Schema.String,
      }),
    },
    refresh: {
      output: Schema.Struct({ started: Schema.Boolean }),
    },
    rotate: {
      output: Schema.Struct({ started: Schema.Boolean }),
    },
  },
})
