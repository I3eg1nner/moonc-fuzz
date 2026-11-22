enum E18 { A; B }
fn f(e : E18) -> Int { match e { A => 18 } }
fn main { println(f(A)) }
