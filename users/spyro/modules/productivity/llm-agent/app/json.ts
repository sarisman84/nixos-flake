/**
 * A number as Nix's `builtins.fromJSON` sees it.
 *
 * Nix keeps a JSON float literal (`1.0`, `0.0`) distinct from an int literal
 * (`1`, `0`), and `toString` renders a float with exactly six decimal places
 * (`1.0` → `"1.000000"`, `0.0` → `"0.000000"`) while an int renders bare
 * (`64` → `"64"`). JavaScript's `JSON.parse` collapses the two to one number,
 * so a naive port would emit `--temperature 1` where the flake emits
 * `--temperature 1.000000`. The parser below tags each number with the kind its
 * literal had, and the generators read that tag to reproduce the flake's output
 * byte-for-byte.
 */
export class NixNum {
  constructor(
    readonly value: number,
    readonly isFloat: boolean,
  ) {}
}

/** A parsed JSON value, with Nix's int/float distinction preserved. */
export type Json =
  | null
  | string
  | boolean
  | NixNum
  | Json[]
  | { [key: string]: Json }

/** True for a JSON object (not an array, not null). */
export function isObject(v: Json): v is { [key: string]: Json } {
  return typeof v === "object" && v !== null && !Array.isArray(v)
}

/** True for a JSON array. */
export function isArray(v: Json): v is Json[] {
  return Array.isArray(v)
}

/** True for a NixNum (any JSON number). */
export function isNum(v: Json): v is NixNum {
  return v instanceof NixNum
}

/** Nix `builtins.isInt`: the literal was an int (no decimal point / exponent). */
export function isInt(v: Json): v is NixNum {
  return isNum(v) && !v.isFloat
}

/** Nix `builtins.isFloat`: the literal was a float. */
export function isFloat(v: Json): v is NixNum {
  return isNum(v) && v.isFloat
}

/** Nix `builtins.isString`. */
export function isString(v: Json): v is string {
  return typeof v === "string"
}

/** Nix `builtins.isBool`. */
export function isBool(v: Json): v is boolean {
  return typeof v === "boolean"
}

/**
 * Nix `toString` on a number: a float renders with six decimal places, an int
 * renders bare. Mirrors the flake's `swapCmd`/generator output exactly.
 */
export function nixToString(v: NixNum): string {
  return v.isFloat ? v.value.toFixed(6) : String(v.value)
}

/**
 * Parse JSON with Nix semantics. A hand-rolled recursive-descent parser rather
 * than `JSON.parse`, because the only thing `JSON.parse` gets wrong for this
 * port is the int/float distinction, and that distinction is load-bearing for
 * the generated `llama-server` argv.
 *
 * Throws on malformed input; callers that want a readable error (the
 * `config.json: invalid JSON` assertion) wrap this in a try/catch.
 */
export function parseNixJson(text: string): Json {
  let i = 0

  const fail = (msg: string): never => {
    throw new SyntaxError(`invalid JSON at offset ${i}: ${msg}`)
  }

  const ws = () => {
    while (i < text.length) {
      const c = text[i]
      if (c === " " || c === "\t" || c === "\n" || c === "\r") i++
      else break
    }
  }

  const parseValue = (): Json => {
    ws()
    if (i >= text.length) fail("unexpected end of input")
    const c = text[i]
    if (c === "{") return parseObject()
    if (c === "[") return parseArray()
    if (c === '"') return parseString()
    if (c === "t") return parseLiteral("true", true)
    if (c === "f") return parseLiteral("false", false)
    if (c === "n") return parseLiteral("null", null)
    return parseNumber()
  }

  const parseObject = (): { [key: string]: Json } => {
    i++ // consume '{'
    const obj: { [key: string]: Json } = {}
    ws()
    if (text[i] === "}") {
      i++
      return obj
    }
    for (;;) {
      ws()
      if (text[i] !== '"') fail("expected object key string")
      const key = parseString()
      ws()
      if (text[i] !== ":") fail("expected ':' after object key")
      i++
      obj[key] = parseValue()
      ws()
      if (text[i] === ",") {
        i++
        continue
      }
      if (text[i] === "}") {
        i++
        return obj
      }
      fail("expected ',' or '}' in object")
    }
  }

  const parseArray = (): Json[] => {
    i++ // consume '['
    const arr: Json[] = []
    ws()
    if (text[i] === "]") {
      i++
      return arr
    }
    for (;;) {
      arr.push(parseValue())
      ws()
      if (text[i] === ",") {
        i++
        continue
      }
      if (text[i] === "]") {
        i++
        return arr
      }
      fail("expected ',' or ']' in array")
    }
  }

  const parseString = (): string => {
    i++ // consume opening quote
    let out = ""
    for (;;) {
      if (i >= text.length) fail("unterminated string")
      const c = text[i]
      if (c === '"') {
        i++
        return out
      }
      if (c === "\\") {
        i++
        const e = text[i]
        if (e === undefined) fail("unterminated escape")
        i++
        switch (e) {
          case '"':
            out += '"'
            break
          case "\\":
            out += "\\"
            break
          case "/":
            out += "/"
            break
          case "b":
            out += "\b"
            break
          case "f":
            out += "\f"
            break
          case "n":
            out += "\n"
            break
          case "r":
            out += "\r"
            break
          case "t":
            out += "\t"
            break
          case "u": {
            const hex = text.slice(i, i + 4)
            if (!/^[0-9a-fA-F]{4}$/.test(hex)) fail("invalid \\u escape")
            out += String.fromCharCode(parseInt(hex, 16))
            i += 4
            break
          }
          default:
            fail(`invalid escape '\\${e}'`)
        }
        continue
      }
      out += c
      i++
    }
  }

  const parseLiteral = (lit: string, value: Json): Json => {
    if (text.slice(i, i + lit.length) !== lit) fail(`invalid literal`)
    i += lit.length
    return value
  }

  const parseNumber = (): NixNum => {
    const start = i
    if (text[i] === "-") i++
    // integer part
    if (text[i] === "0") {
      i++
    } else if (text[i] >= "1" && text[i] <= "9") {
      while (i < text.length && text[i] >= "0" && text[i] <= "9") i++
    } else {
      fail("invalid number")
    }
    let isFloat = false
    // fraction part
    if (text[i] === ".") {
      isFloat = true
      i++
      if (!(text[i] >= "0" && text[i] <= "9")) fail("expected digit after '.'")
      while (i < text.length && text[i] >= "0" && text[i] <= "9") i++
    }
    // exponent part
    if (text[i] === "e" || text[i] === "E") {
      isFloat = true
      i++
      if (text[i] === "+" || text[i] === "-") i++
      if (!(text[i] >= "0" && text[i] <= "9")) fail("expected digit in exponent")
      while (i < text.length && text[i] >= "0" && text[i] <= "9") i++
    }
    const literal = text.slice(start, i)
    return new NixNum(Number(literal), isFloat)
  }

  const value = parseValue()
  ws()
  if (i < text.length) fail("trailing characters")
  return value
}
