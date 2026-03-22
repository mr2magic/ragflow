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

from agent.tools.newsapi import NewsAPI, NewsAPIParam
from test.testcases.test_tools.conftest import make_tool


@pytest.fixture()
def tool(mock_canvas):
    return make_tool(NewsAPI, NewsAPIParam, mock_canvas, api_key="test-news-key")


def _mock_response(articles):
    resp = MagicMock()
    resp.raise_for_status = MagicMock()
    resp.json.return_value = {"status": "ok", "articles": articles}
    return resp


class TestNewsAPIParam:
    def test_defaults(self):
        param = NewsAPIParam()
        assert param.language == "en"
        assert param.sort_by == "relevancy"
        assert param.max_results == 6
        assert param.meta["name"] == "news_search"

    def test_api_key_from_env(self, monkeypatch):
        monkeypatch.setenv("NEWSAPI_API_KEY", "env-key")
        param = NewsAPIParam()
        assert param.api_key == "env-key"

    def test_api_key_default_empty(self, monkeypatch):
        monkeypatch.delenv("NEWSAPI_API_KEY", raising=False)
        param = NewsAPIParam()
        assert param.api_key == ""

    def test_get_input_form(self):
        form = NewsAPIParam().get_input_form()
        assert "query" in form


class TestNewsAPI:
    def test_empty_query_returns_empty(self, tool):
        result = tool._invoke(query="")
        assert result == ""
        assert tool.output("formalized_content") == ""

    def test_successful_search(self, tool):
        articles = [
            {
                "title": "Big News",
                "url": "https://news.example.com/1",
                "content": "Full article text",
                "description": "Short desc",
            }
        ]
        with patch("requests.get", return_value=_mock_response(articles)):
            tool._invoke(query="technology")

        tool._retrieve_chunks.assert_called_once()
        assert tool.output("json") == articles

    def test_content_fallback_to_description(self, tool):
        articles = [
            {
                "title": "T",
                "url": "u",
                "content": None,
                "description": "The description",
            }
        ]
        with patch("requests.get", return_value=_mock_response(articles)):
            tool._invoke(query="test")

        call_args = tool._retrieve_chunks.call_args
        get_content = call_args.kwargs["get_content"]
        assert get_content(articles[0]) == "The description"

    def test_content_empty_when_both_none(self, tool):
        articles = [{"title": "T", "url": "u", "content": None, "description": None}]
        with patch("requests.get", return_value=_mock_response(articles)):
            tool._invoke(query="test")

        call_args = tool._retrieve_chunks.call_args
        get_content = call_args.kwargs["get_content"]
        assert get_content(articles[0]) == ""

    def test_api_key_passed_in_params(self, tool):
        with patch("requests.get", return_value=_mock_response([])) as mock_get:
            tool._invoke(query="test")
        params = mock_get.call_args.kwargs["params"]
        assert params["apiKey"] == "test-news-key"

    def test_language_and_sort_overrides(self, tool):
        with patch("requests.get", return_value=_mock_response([])) as mock_get:
            tool._invoke(query="test", language="fr", sort_by="publishedAt")
        params = mock_get.call_args.kwargs["params"]
        assert params["language"] == "fr"
        assert params["sortBy"] == "publishedAt"

    def test_http_error_sets_error_output(self, tool):
        tool._param.max_retries = 0
        tool._param.delay_after_error = 0
        with patch("requests.get", side_effect=requests.HTTPError("429")):
            result = tool._invoke(query="test")
        assert "error" in result.lower()
        assert tool.output("_ERROR") is not None

    def test_thoughts(self, tool):
        tool.get_input = MagicMock(return_value={"query": "breaking news"})
        assert "breaking news" in tool.thoughts()
