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

from agent.tools.brave import BraveSearch, BraveSearchParam
from test.testcases.test_tools.conftest import make_tool


@pytest.fixture()
def tool(mock_canvas):
    return make_tool(BraveSearch, BraveSearchParam, mock_canvas, api_key="test-brave-key")


def _mock_response(results):
    resp = MagicMock()
    resp.raise_for_status = MagicMock()
    resp.json.return_value = {"web": {"results": results}}
    return resp


class TestBraveSearchParam:
    def test_defaults(self):
        param = BraveSearchParam()
        assert param.count == 6
        assert param.search_lang == "en"
        assert param.freshness == ""
        assert param.meta["name"] == "brave_search"

    def test_api_key_from_env(self, monkeypatch):
        monkeypatch.setenv("BRAVE_SEARCH_API_KEY", "env-key")
        param = BraveSearchParam()
        assert param.api_key == "env-key"

    def test_api_key_default_empty(self, monkeypatch):
        monkeypatch.delenv("BRAVE_SEARCH_API_KEY", raising=False)
        param = BraveSearchParam()
        assert param.api_key == ""

    def test_get_input_form(self):
        param = BraveSearchParam()
        form = param.get_input_form()
        assert "query" in form


class TestBraveSearch:
    def test_empty_query_returns_empty(self, tool):
        result = tool._invoke(query="")
        assert result == ""
        assert tool.output("formalized_content") == ""

    def test_successful_search(self, tool):
        results = [
            {"title": "Test", "url": "https://example.com", "description": "A result", "score": 0.9}
        ]
        with patch("requests.get", return_value=_mock_response(results)):
            tool._invoke(query="test query")

        tool._retrieve_chunks.assert_called_once()
        assert tool.output("json") == results

    def test_freshness_param_included_when_set(self, tool):
        results = [{"title": "T", "url": "u", "description": "d", "score": 1}]
        with patch("requests.get", return_value=_mock_response(results)) as mock_get:
            tool._invoke(query="news", freshness="pd")
        call_kwargs = mock_get.call_args
        assert call_kwargs.kwargs["params"]["freshness"] == "pd"

    def test_freshness_omitted_when_empty(self, tool):
        results = []
        with patch("requests.get", return_value=_mock_response(results)) as mock_get:
            tool._invoke(query="test", freshness="")
        call_kwargs = mock_get.call_args
        assert "freshness" not in call_kwargs.kwargs["params"]

    def test_extra_snippets_used_for_content(self, tool):
        results = [
            {
                "title": "T",
                "url": "u",
                "description": "desc",
                "extra_snippets": ["snippet text"],
                "score": 1,
            }
        ]
        with patch("requests.get", return_value=_mock_response(results)):
            tool._invoke(query="test")

        call_args = tool._retrieve_chunks.call_args
        get_content = call_args.kwargs["get_content"]
        assert get_content(results[0]) == "snippet text"

    def test_http_error_sets_error_output(self, tool):
        tool._param.max_retries = 0
        tool._param.delay_after_error = 0
        with patch("requests.get", side_effect=requests.HTTPError("500")):
            result = tool._invoke(query="test")
        assert "error" in result.lower()
        assert tool.output("_ERROR") is not None

    def test_count_and_lang_passed_to_api(self, tool):
        with patch("requests.get", return_value=_mock_response([])) as mock_get:
            tool._invoke(query="test", count=10, search_lang="fr")
        params = mock_get.call_args.kwargs["params"]
        assert params["count"] == 10
        assert params["search_lang"] == "fr"

    def test_api_key_in_header(self, tool):
        with patch("requests.get", return_value=_mock_response([])) as mock_get:
            tool._invoke(query="test")
        headers = mock_get.call_args.kwargs["headers"]
        assert headers["X-Subscription-Token"] == "test-brave-key"

    def test_thoughts(self, tool):
        tool.get_input = MagicMock(return_value={"query": "hello"})
        assert "hello" in tool.thoughts()
