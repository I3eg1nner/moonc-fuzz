///|
/// Invariants the methodology note depends on.  If any of these break, the
/// numbers in `findings/methodology.md` are no longer about this code.

///|
test "rule of three upper bound" {
  assert_eq(upper95_zero(0), 0.0)
  assert_eq(upper95_zero(270), 3.0 / 270.0)
  assert_true(upper95_zero(270) < 0.0112)
  assert_true(upper95_zero(10) > upper95_zero(100))
}

///|
test "every oracle has a positive and no oracle has a control hit" {
  for s in @judge.registry() {
    let mut positives = 0
    let mut false_alarms = 0
    for p in @judge.probes() {
      if p.spec == s.id {
        let n = @judge.check(s, p.obs).length()
        if p.want_hit {
          positives += 1
          assert_true(n > 0)
        } else if n > 0 {
          false_alarms += 1
        }
      }
    }
    assert_true(positives > 0)
    assert_eq(false_alarms, 0)
  }
}

///|
test "boundary vectors are total over their axes" {
  let lines = boundaries()
  assert_eq(lines.length(), 10)
  // Each line is a vector over one axis.  The two negative controls are all-N
  // by construction; every other line must show the flip, otherwise it is a
  // constant and says nothing about a threshold.
  for l in lines {
    assert_true(l.contains(":Y") || l.contains(":N"))
    let control = l.contains("not alive") || l.contains("no output owed")
    if control {
      assert_false(l.contains(":Y"))
    } else {
      assert_true(l.contains(":Y"))
      assert_true(l.contains(":N"))
    }
  }
}

///|
test "crash does not read 139 as a signal" {
  let as_signal = @judge.observation(
    "build", -11, false, 100L, 90L, 0, false, false, "", "",
  )
  let as_code = @judge.observation(
    "build", 139, false, 100L, 90L, 0, false, false, "", "",
  )
  assert_true(fires("crash", as_signal))
  assert_false(fires("crash", as_code))
}

///|
test "busy and blocked split exactly at half wall time" {
  let below = @judge.observation(
    "lsp", -1, true, 3000L, 1499L, 0, true, true, "", "",
  )
  let at = @judge.observation(
    "lsp", -1, true, 3000L, 1500L, 0, true, true, "", "",
  )
  assert_true(fires("blocked_stall", below))
  assert_false(fires("busy_hang", below))
  assert_true(fires("busy_hang", at))
  assert_false(fires("blocked_stall", at))
}
