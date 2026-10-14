Implemented and committed the dispatch refactor as `bd7c7c2754b9a3e98b659b579b1a58108c844e66` (`refactor(silod): dispatch methods through domain handlers`).

The six domain modules now have exclusive ownership routing, and [HandlerContext](</Users/polarzero/silo-work/p2-dispatch/app/SiloUI/src-tauri/silod/src/methods/mod.rs>) provides engine, job, event, client, decoding, error-mapping, and job-start helpers. Owned methods remain unsupported until their domain tracks implement them; the existing nine built-in methods and capability list are preserved. The routing test covers all 146 API methods.

The full workspace suite passed: **2,465 passed, 30 ignored, 0 failed**. Formatting and `cargo check -p silod` passed. Tests used synthetic GitHub build values; no app or VM was launched.

The requested report, including the exact handler signature, is at [p2-dispatch-keystone.md](</Users/polarzero/code/projects/lookout/docs/design/silo-api/reports/p2-dispatch-keystone.md>).