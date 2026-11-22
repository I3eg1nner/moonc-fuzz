///|
/// `p(false, false, true)` is `false && (false || true)`, i.e. false,
/// so this postcondition should not be provable.
pub fn f(x : Int) -> Int where {
  proof_ensure: result => p(false, false, true),
} {
  x
}
