trait T23 { f(Self) -> Int }
struct S23 { x23 : Int }
fn[A : T23] g(a : A) -> Int { a.f() }
fn main { println(g(S23::{x23:23})) }
