trait T28 { f(Self) -> Int }
struct S28 { x28 : Int }
fn[A : T28] g(a : A) -> Int { a.f() }
fn main { println(g(S28::{x28:28})) }
