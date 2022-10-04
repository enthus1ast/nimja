discard """
  joinable: false
"""
import ../../src/nimja
import unittest
import strutils

# suite "scope":
#   test "simple if":x

suite "scope":
  test "1":
    check "POSTFOO" == tmpls """
      {%- scope -%}
        {% let httpMethod = "POST" %}
        {{- httpMethod -}}
      {%- endscope -%}
      {%- let httpMethod = "FOO" -%}
      {{- httpMethod -}}
    """
  test "2 named":
    # we break out of a scope prematurely
    check "foo" == tmpls """
      {%- scope foo -%}
        foo
        {%- break foo -%}
        baa
      {%- endscope -%}
    """
  test "3 named":
    # we break out of a scope prematurely
    check "foo" == tmpls """
      {%- scope foo -%}
        foo
        {%- scope baa -%}
        {%- break foo -%}
        baa
        {%- endscope -%}
      {%- endscope -%}
    """
  test "4 scope with import":
    check "foo" == tmpls """
      {%- scope foo -%}
        {%- importnimja "foo.nimja" -%}
      {%- endscope -%}
    """
      
  