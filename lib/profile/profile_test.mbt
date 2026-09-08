///|
/// The algebra. A profile is a set that only grows, and the named ones stack.

///|
test "core has nothing" {
  assert_eq(@profile.core.features(), [])
  assert_false(@profile.core.has(ChainedBoolean))
}

///|
test "adding is idempotent and monotone" {
  let p = @profile.core.adding([ChainedBoolean])
  assert_true(p.has(ChainedBoolean))
  assert_eq(p.features(), [ChainedBoolean])
  // Adding what is already there changes nothing.
  assert_eq(p.adding([ChainedBoolean]).features(), p.features())
  // And adding nothing changes nothing.
  assert_eq(p.adding([]).features(), p.features())
}

///|
/// Every named profile contains `core`, and each contains the one below it.
///
/// The stacking is structural -- `pending` is written as `core.adding(...)` --
/// so this cannot fail while the definitions stand. It is here to fail LOUDLY
/// if someone ever writes one of them independently.
test "the named profiles stack" {
  let ladder = [@profile.core, @profile.pending()]
  for i, p in ladder {
    assert_true(p.contains(@profile.core))
    if i > 0 {
      assert_true(p.contains(ladder[i - 1]))
    }
  }
  // And the stacking is strict: `pending` is more than `core`.
  assert_false(@profile.core.contains(@profile.pending()))
}

///|
test "by_name answers to every name it publishes" {
  for name in @profile.names {
    match @profile.by_name(name) {
      Some(_) => ()
      None => fail("no profile named '" + name + "'")
    }
  }
  assert_eq(@profile.by_name("no-such-profile"), None)
  // The specification's own name for itself, too.
  assert_true(@profile.by_name("purepy").unwrap().features().is_empty())
}

///|
/// `features` is what `pure-py profiles` prints and what a person compares
/// between two profiles, so the order is a promise.
test "features answers in tag order" {
  let p = @profile.core.adding([ChainedBoolean, ChainedBoolean])
  assert_eq(p.features().map(Feature::name), ["chained-boolean"])
}

///|
/// The hint the CLI and the playground print. Keyed on the feature string the
/// sieve passes to `not_yet`, so a rename there must be a rename here.
test "accepted_by names the profile that opens the gate" {
  assert_eq(@profile.accepted_by("chained boolean operator"), Some("pending"))
  assert_eq(@profile.accepted_by("f-strings"), Some("pending"))
  // A feature no profile has yet answers with nothing, so the hint stays
  // silent rather than pointing somewhere that would not help.
  assert_eq(@profile.accepted_by("*args"), None)
  // And a prohibition is never a profile away, so it never gets a hint.
  assert_eq(@profile.accepted_by("for loops prohibited"), None)
}
