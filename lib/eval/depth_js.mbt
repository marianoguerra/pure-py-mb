///|
/// How deep a PurePy call stack may go by default, on a JavaScript host.
///
/// Twelve, which is not a typo. `wasm`, `wasm-gc` and `js` all run on a
/// JavaScript engine's stack -- about a megabyte where a native thread has
/// eight -- and the `async` transform spends roughly a dozen host frames per
/// guest call. Measured under Node, over a program that recurses with a small
/// expression in each frame:
///
/// | backend | debug | release |
/// |---|---|---|
/// | `wasm-gc` | about 26 guest calls | about 130 |
/// | `wasm` | about 26 | — |
/// | `js` | about 40 | — |
///
/// Why the default is the conservative one rather than the useful one: on a
/// native thread an overflow is a crash the developer sees, but here it is a
/// `RangeError` that no MoonBit code can catch, and in a browser it takes the
/// tab with it. `a call stack deeper than 12` is an ordinary termination that
/// a page can render and a program can be rewritten around. Twelve is under
/// half the tightest measured ceiling, which is the same margin the native
/// number has.
///
/// This is the floor, not a recommendation. An embedder that ships a release
/// build and knows it -- the playground does -- measures its own ceiling and
/// passes `max_depth` accordingly.
pub let default_max_depth : Int = 12
