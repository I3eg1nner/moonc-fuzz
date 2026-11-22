trait T1 { f(Self) -> Int }
struct S1 { x1 : Int }
fn[A : T1] g(a : A) -> Int { a.f() }
fn main { println(g(S1::{x1:1})) }
