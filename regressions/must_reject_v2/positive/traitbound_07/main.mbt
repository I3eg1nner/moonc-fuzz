trait T7 { f(Self) -> Int }
struct S7 { x7 : Int }
fn[A : T7] g(a : A) -> Int { a.f() }
fn main { println(g(S7::{x7:7})) }
