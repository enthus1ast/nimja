discard """
  joinable: false
"""
import ../../src/nimja
import unittest
import strutils

# suite "scope":
#   test "simple if":x
echo tmpls """
{%- scope %}
  {% let httpMethod = "POST" %}
  {{- httpMethod -}}
{% endscope -%}
{%- let httpMethod = "FOO" -%}
{{- httpMethod -}}
"""