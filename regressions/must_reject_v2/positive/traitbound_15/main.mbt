trait T15 { f(Self) -> Int }
struct S15 { x15 : Int }
fn[A : T15] g(a : A) -> Int { a.f() }
fn main { println(g(S15::{x15:15})) }
