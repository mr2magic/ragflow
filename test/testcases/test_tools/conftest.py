#
#  Copyright 2024 The InfiniFlow Authors. All Rights Reserved.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#
"""
Shared fixtures for agent tool unit tests.

Tools require a Canvas instance. We mock it here so tests run without
a live database, Redis, or Elasticsearch connection.
"""
import sys
import types
from unittest.mock import MagicMock, patch
import pytest

# ---------------------------------------------------------------------------
# Stub out heavy / unavailable dependencies before any agent module is loaded.
# agent.component.base (pulled in by agent.tools.base) needs pandas, etc.
# We make each stub auto-return MagicMock for any attribute so callers don't
# crash on things like nest_asyncio.apply() or strenum.StrEnum.
# ---------------------------------------------------------------------------
def _make_magic_stub(name):
    mod = types.ModuleType(name)

    def _getattr(attr):
        m = MagicMock()
        setattr(mod, attr, m)
        return m

    mod.__getattr__ = _getattr
    return mod


_STUB_MODULES = [
    # Third-party optional deps
    "Bio", "Bio.Entrez",
    "tavily",
    "arxiv",
    "jinja2", "jinja2.sandbox",
    "reportlab", "reportlab.lib", "reportlab.lib.pagesizes", "reportlab.platypus",
    "json_repair",
    "nest_asyncio",
    "quart",
    "serpapi",
    "scholarly",
    "akshare",
    "wencai",
    "yfinance",
    "tiktoken",
    # Internal RAGFlow modules not needed for tool unit tests
    "rag.prompts",
    "rag.prompts.generator",
    "rag.nlp",
    "rag.nlp.rag_tokenizer",
    "common.mcp_tool_call_conn",
    "common.token_utils",
]

for _mod in _STUB_MODULES:
    if _mod not in sys.modules:
        sys.modules[_mod] = _make_magic_stub(_mod)


@pytest.fixture()
def mock_canvas():
    """A minimal Canvas mock that satisfies ToolBase requirements."""
    canvas = MagicMock()
    canvas.add_reference = MagicMock()
    canvas.get_component_name = MagicMock(return_value="test-tool")
    return canvas


@pytest.fixture(autouse=True)
def patch_canvas_import():
    """Prevent ToolBase.__init__ from importing the real Canvas class."""
    with patch("agent.tools.base.ToolBase.__init__", lambda self, canvas, id, param: None):
        yield


def make_tool(tool_cls, param_cls, canvas, api_key="test-key", **param_overrides):
    """
    Instantiate a tool with a mocked canvas, bypassing the real __init__.
    Sets up the minimal attributes ToolBase needs.
    """
    param = param_cls.__new__(param_cls)
    param_cls.__init__(param)
    if api_key is not None:
        param.api_key = api_key
    for k, v in param_overrides.items():
        setattr(param, k, v)

    tool = tool_cls.__new__(tool_cls)
    tool._canvas = canvas
    tool._id = "test-id"
    tool._param = param

    # Wire up set_output / output via the param's outputs dict
    tool._param.outputs = {}

    def _set_output(key, value):
        tool._param.outputs[key] = {"value": value}

    def _output(var_nm=None):
        if var_nm is None:
            return tool._param.outputs
        return tool._param.outputs.get(var_nm, {}).get("value")

    def _check_if_canceled(msg=""):
        return False

    def _get_input(key=None):
        return {}

    tool.set_output = _set_output
    tool.output = _output
    tool.check_if_canceled = _check_if_canceled
    tool.get_input = _get_input
    tool._retrieve_chunks = MagicMock()

    return tool
