fn compute() -> String {
  let s = "héllo 中文 😀"
  let t = s + "!"
  "\{s.length()}|\{t}|\{s[1:4]}|\{s[0:1]}"
}
fn main { println(compute()) }
