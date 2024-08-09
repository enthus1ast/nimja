discard """
  joinable: false
"""
include ../../src/nimja/parser
doAssertRaises ValueError:
  discard compile("{%block foo%}{%endblock%}{%block foo%}{%endblock%}")

doAssertRaises ValueError:
  discard compile("{%block foo%}{%block foo%}{%endblock%}{%endblock%}")

###

doAssertRaises ValueError:
  discard compile("{% extends foo %}{% extends baa %}")

doAssertRaises ValueError:
  discard compile("FOO{% extends foo %}BAA{% extends baa %}")

###

doAssertRaises ValueError:
  discard compile("{%if%}{%if%}{%endif%}")

doAssertRaises ValueError:
  discard compile("{%if%}{%endif%}{%endif%}")

###

doAssertRaises ValueError:
  discard compile("{%for%}{%for%}{%endfor%}")

doAssertRaises ValueError:
  discard compile("{%for%}{%endfor%}{%endfor%}")

###

doAssertRaises ValueError:
  discard compile("{%while%}{%while%}{%endwhile%}")

doAssertRaises ValueError:
  discard compile("{%while%}{%endwhile%}{%endwhile%}")

