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
from unittest.mock import MagicMock, patch

import pytest
import requests

from agent.tools.jinareader import JinaReader, JinaReaderParam
from test.testcases.test_tools.conftest import make_tool


@pytest.fixture()
def tool(mock_canvas):
    return make_tool(JinaReader, JinaReaderParam, mock_canvas, api_key="")


def _mock_response(text):
    resp = MagicMock()
    resp.raise_for_status = MagicMock()
    resp.text = text
    return resp


class TestJinaReaderParam:
    def test_defaults(self):
        param = JinaReaderParam()
        assert param.meta["name"] == "jina_reader"

    def test_api_key_from_env(self, monkeypatch):
        monkeypatch.setenv("JINA_API_KEY", "jina-secret")
        param = JinaReaderParam()
        assert param.api_key == "jina-secret"

    def test_api_key_default_empty(self, monkeypatch):
        monkeypatch.delenv("JINA_API_KEY", raising=False)
        param = JinaReaderParam()
        assert param.api_key == ""

    def test_get_input_form(self):
        form = JinaReaderParam().get_input_form()
        assert "url" in form


class TestJinaReader:
    def test_empty_url_returns_empty(self, tool):
        result = tool._invoke(url="")
        assert result == ""
        assert tool.output("formalized_content") == ""

    def test_successful_fetch(self, tool):
        page_content = "# Article Title\n\nSome article body."
        with patch("requests.get", return_value=_mock_response(page_content)):
            tool._invoke(url="https://example.com/article")

        tool._retrieve_chunks.assert_called_once()
        results = tool.output("json")
        assert results[0]["content"] == page_content
        assert results[0]["url"] == "https://example.com/article"

    def test_jina_url_constructed_correctly(self, tool):
        with patch("requests.get", return_value=_mock_response("content")) as mock_get:
            tool._invoke(url="https://example.com/page")
        called_url = mock_get.call_args.args[0]
        assert called_url == "https://r.jina.ai/https://example.com/page"

    def test_no_auth_header_without_api_key(self, tool):
        tool._param.api_key = ""
        with patch("requests.get", return_value=_mock_response("ok")) as mock_get:
            tool._invoke(url="https://example.com")
        headers = mock_get.call_args.kwargs["headers"]
        assert "Authorization" not in headers

    def test_auth_header_with_api_key(self, tool):
        tool._param.api_key = "my-jina-key"
        with patch("requests.get", return_value=_mock_response("ok")) as mock_get:
            tool._invoke(url="https://example.com")
        headers = mock_get.call_args.kwargs["headers"]
        assert headers["Authorization"] == "Bearer my-jina-key"

    def test_accept_header_is_text_plain(self, tool):
        with patch("requests.get", return_value=_mock_response("ok")) as mock_get:
            tool._invoke(url="https://example.com")
        headers = mock_get.call_args.kwargs["headers"]
        assert headers["Accept"] == "text/plain"

    def test_leading_slash_stripped_from_url(self, tool):
        with patch("requests.get", return_value=_mock_response("ok")) as mock_get:
            tool._invoke(url="/example.com/page")
        called_url = mock_get.call_args.args[0]
        assert called_url == "https://r.jina.ai/example.com/page"

    def test_http_error_sets_error_output(self, tool):
        tool._param.max_retries = 0
        tool._param.delay_after_error = 0
        with patch("requests.get", side_effect=requests.HTTPError("404")):
            result = tool._invoke(url="https://example.com/missing")
        assert "error" in result.lower()
        assert tool.output("_ERROR") is not None

    def test_thoughts(self, tool):
        tool.get_input = MagicMock(return_value={"url": "https://example.com"})
        assert "https://example.com" in tool.thoughts()
