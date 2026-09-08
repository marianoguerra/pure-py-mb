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

///|
/// How many steps a run may take by default.
///
/// A step is one move of the machine in `machine.mbt`: evaluate a
/// sub-expression, hand a value to a frame, enter a call, bind a statement.
/// `max_depth` bounds how DEEP a guest may go and this bounds how LONG it may
/// take, which are different runaways and only one of them used to have an
/// answer.
///
/// PurePy has no loops, so for a long time the only way to run forever was to
/// recurse, and `max_depth` caught that. It is not the only way: a
/// comprehension over a long sequence loops without recursing, and used to run
/// to completion however long that took -- which on a browser tab is a page
/// that stops answering, with no message and nothing to interrupt it.
///
/// A hundred million is a policy, like `max_depth`'s ten thousand: far more
/// than any program a person is waiting on, few enough that a runaway ends in
/// an answer rather than in a hang. A host that knows better passes
/// `max_steps` -- a notebook cell wants a much smaller one, and a batch job on
/// a native thread may want none of it.
///
/// It is DETERMINISTIC, which a wall-clock timeout would not be. Two runs of
/// the same program over the same host answers take the same number of steps
/// and stop in the same place, so a guest that hits the limit hits it
/// reproducibly and a test can pin it.
pub let default_max_steps : Int = 100_000_000
