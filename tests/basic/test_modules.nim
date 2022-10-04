discard """
  joinable: false
"""
import ../../src/nimja
import macros

const foo = getProjectPath()
echo "test_modules:", foo

import moduletest/module1

doStuffModule1()
