trait T10 { f(Self) -> Int }
struct S10 { x10 : Int }
fn[A : T10] g(a : A) -> Int { a.f() }
fn main { println(g(S10::{x10:10})) }
