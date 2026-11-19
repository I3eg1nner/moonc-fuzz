///|
/// One differential case: a complete program that prints labelled values.
/// The label is part of the compared output, so a divergence names the
/// operation instead of just "stdout differs".
pub(all) struct Case {
  id : String
  family : String
  src : String
}

///|
/// Helpers embedded in every program: bit patterns for floats and a Bool
/// spelling that does not depend on `Show` formatting.
fn prelude() -> String {
  let s =
    #|fn b(x : Bool) -> String {
    #|  if x {
    #|    "1"
    #|  } else {
    #|    "0"
    #|  }
    #|}
    #|
    #|fn u(x : UInt64) -> String {
    #|  x.to_string()
    #|}
    #|
  s
}
