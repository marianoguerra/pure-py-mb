///|
/// How deep a PurePy call stack may go by default, on a JavaScript host.
///
/// Twelve, which is not a typo, and which is a floor rather than an estimate
/// of what your embedding can do. `wasm`, `wasm-gc` and `js` all run on a
/// JavaScript engine's stack -- about a megabyte where a native thread has
/// eight -- and the `async` transform spends roughly a dozen host frames per
/// guest call.
///
/// What the ceiling actually is depends on two things, and the second one is
/// the surprise. Measured under Node over a program that recurses with a
/// small expression in each frame:
///
/// | how the evaluator is called | debug | release | release + `-Oz` |
/// |---|---|---|---|
/// | under `moon test` | about 26 | about 130 | — |
/// | as a bare export, nothing beneath it | about 370 | about 600 | about 780 |
///
/// The build matters, as expected. The CALLER matters more: the same module
/// holds fourteen times as many guest calls when it is entered directly as
/// it does under a test harness, because whatever is already on the stack is
/// stack the guest does not get. An embedder measuring one and shipping the
/// other is measuring the wrong number in either direction.
///
/// So the default is the tightest of them, because that is the one a
/// consumer reaches without deciding to: `moon test --target wasm-gc` on a
/// debug build, where the ceiling really is about 26. Twelve is under half of
/// it, the same margin the native number keeps.
///
/// Why the conservative end rather than the useful one: on a native thread an
/// overflow is a crash the developer sees, but here it is a `RangeError` that
/// no MoonBit code can catch, and in a browser it takes the tab. `a call
/// stack deeper than 12` is an ordinary termination that a page can render
/// and a program can be rewritten around.
///
/// **Measure your own and pass `max_depth`.** Call your module the way your
/// application calls it, at increasing depths, until the engine throws; take
/// about a third. The playground does exactly that and passes 250.
pub let default_max_depth : Int = 12
