trait T22 { f(Self) -> Int }
struct S22 { x22 : Int }
fn[A : T22] g(a : A) -> Int { a.f() }
fn main { println(g(S22::{x22:22})) }
