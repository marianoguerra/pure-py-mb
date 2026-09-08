///|
/// How deep a PurePy call stack may go by default.
///
/// PurePy has no loops, so recursion is the only iteration a guest has, and
/// this is the bound on it. Past it a run ends undefined -- `a call stack
/// deeper than 10000` -- which is an answer a person can read, a page can
/// render and a program can be rewritten around.
///
/// **One number, on every backend.** It used to be two, 500 on a native
/// thread and 12 on the three that run on a JavaScript engine, because the
/// evaluator recursed and the real limit was the HOST's stack: a JavaScript
/// engine holds two orders of magnitude fewer frames than a native thread, and
/// overflowing one throws a `RangeError` no MoonBit code can catch, taking a
/// browser tab with it. That number could not be chosen, only measured -- and
/// re-measured whenever the evaluator changed shape, since a frame is sized by
/// the whole function.
///
/// The evaluator keeps its continuation on the heap now (`machine.mbt`), so
/// the host's stack does not grow with the guest's recursion and there is
/// nothing left for the backend to decide. Ten thousand is a policy: deep
/// enough that no reasonable program meets it, shallow enough that a runaway
/// stops in an array of ten thousand frames rather than in an out-of-memory.
/// A caller who wants a different one passes `max_depth`.
pub let default_max_depth : Int = 10000
