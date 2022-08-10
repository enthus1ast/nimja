import macros, strutils
macro pnodeGenRepr*(node: untyped) =
  proc aux(n: NimNode, res: var string, level: int) =
    res.add "  ".repeat(level)
    case n.kind:
      of nnkIdent:
        res.add "graph.getIdent(\""
        res.add n.strVal()
        res.add "\")"

      of nnkCharLit .. nnkUInt64Lit:
        res.add "newIntNode("
        res.add ($n.kind)[1 .. ^1]
        res.add ", "
        res.add $n.intVal()
        res.add ")"

      of nnkFloatLit .. nnkFloat128Lit:
        res.add "newFloatNode"
        res.add $n.floatVal()
        res.add ", "
        res.add ($n.kind)[1 .. ^1]
        res.add ")"

      of nnkStrLit .. nnkTripleStrLit:
        res.add "newStrNode(\""
        res.add n.strVal()
        res.add "\", "
        res.add ($n.kind)[1 .. ^1]
        res.add ")"

      of nnkEmpty:
        res.add "nkEmpty.newTree()"

      else:
        res.add ($n.kind)[1..^1]
        res.add ".newTree(\n"
        for idx, sub in n:
          aux(sub, res, level + 1)
          if idx < n.len - 1:
            res.add ",\n"

        res.add ")"

  var res: string
  aux(node, res, 1)
  # echo res


# pnodeGenRepr:
#   add(result, $myVar)