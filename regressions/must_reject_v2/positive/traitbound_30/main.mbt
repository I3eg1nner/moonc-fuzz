trait T30 { f(Self) -> Int }
struct S30 { x30 : Int }
fn[A : T30] g(a : A) -> Int { a.f() }
fn main { println(g(S30::{x30:30})) }
