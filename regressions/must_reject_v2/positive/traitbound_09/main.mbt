trait T9 { f(Self) -> Int }
struct S9 { x9 : Int }
fn[A : T9] g(a : A) -> Int { a.f() }
fn main { println(g(S9::{x9:9})) }
