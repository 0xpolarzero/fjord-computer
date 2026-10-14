Integrated the five branches with no-ff merges in the requested order. The cross-track fixes and each requested module extraction are committed; `engine/integration` is clean at `18b45bc4`.

All gates passed: Cargo tests (2,229 passed, 30 ignored), formatting, Node 24.21 typecheck and lint, and Vitest (2,764 passed). Lint reported six warnings. The only frontend changes were source-contract expectations updated for relocated command adapters.

The Tauri scan still finds references outside `src/commands/` and `main.rs` in `app_menu.rs`, `engine_context.rs`, `linux_menu.rs`, `single_instance.rs`, `status_panel.rs`, `titlebar.rs`, `tray.rs`, and `window_material.rs`. The requested extracted engine modules are clear.

The integration report is [e-integration.md](/Users/polarzero/code/projects/lookout/docs/design/silo-api/reports/e-integration.md).