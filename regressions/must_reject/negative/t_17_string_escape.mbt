fn compute() -> String {
  let a = "tab\there"
  let b = "nl\nend"
  let c = "\u{1F600}"
  let d = "quote\"inside"
  "\{a.length()}|\{b.length()}|\{c}|\{d.length()}"
}
fn main { println(compute()) }
