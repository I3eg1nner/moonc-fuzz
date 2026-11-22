trait T19 { f(Self) -> Int }
struct S19 { x19 : Int }
fn[A : T19] g(a : A) -> Int { a.f() }
fn main { println(g(S19::{x19:19})) }
