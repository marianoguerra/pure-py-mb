///|
/// How deep a PurePy call stack may go by default, on a native thread.
///
/// Half Python's own limit of a thousand. Evaluation is `async`, so that a
/// host function may suspend, and the compiler's transform makes each guest
/// call cost several machine frames where a direct call cost one. Measured
/// on a native thread's default 8 MB, over a program that recurses with a
/// small expression in each frame:
///
/// | build | ceiling |
/// |---|---|
/// | debug | about 1050 guest calls |
/// | release | over 6000 |
///
/// The limit exists to turn a stack overflow into an answer a person can
/// read, so it has to sit below the tightest ceiling a consumer might build,
/// and a debug build is one anybody can build. A release build holds ten
/// times this: a caller that knows what it built should raise it.
///
/// The JavaScript-hosted backends get a number of their own, in
/// `depth_js.mbt`, because their ceiling is two orders of magnitude lower.
pub let default_max_depth : Int = 500
