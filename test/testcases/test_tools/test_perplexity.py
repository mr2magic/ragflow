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

from agent.tools.perplexity import PerplexitySearch, PerplexitySearchParam
from test.testcases.test_tools.conftest import make_tool


@pytest.fixture()
def tool(mock_canvas):
    return make_tool(PerplexitySearch, PerplexitySearchParam, mock_canvas, api_key="test-pplx-key")


def _mock_openai_response(content, citations=None):
    msg = MagicMock()
    msg.content = content
    choice = MagicMock()
    choice.message = msg
    response = MagicMock()
    response.choices = [choice]
    response.citations = citations or []
    return response


class TestPerplexitySearchParam:
    def test_defaults(self):
        param = PerplexitySearchParam()
        assert param.model == "sonar"
        assert param.meta["name"] == "perplexity_search"

    def test_api_key_from_env(self, monkeypatch):
        monkeypatch.setenv("PERPLEXITY_API_KEY", "env-key")
        param = PerplexitySearchParam()
        assert param.api_key == "env-key"

    def test_api_key_default_empty(self, monkeypatch):
        monkeypatch.delenv("PERPLEXITY_API_KEY", raising=False)
        param = PerplexitySearchParam()
        assert param.api_key == ""

    def test_get_input_form(self):
        form = PerplexitySearchParam().get_input_form()
        assert "query" in form


class TestPerplexitySearch:
    def test_empty_query_returns_empty(self, tool):
        result = tool._invoke(query="")
        assert result == ""
        assert tool.output("formalized_content") == ""

    def test_successful_search_no_citations(self, tool):
        mock_resp = _mock_openai_response("Answer text", citations=[])
        with patch("agent.tools.perplexity.OpenAI") as mock_openai_cls:
            mock_client = MagicMock()
            mock_client.chat.completions.create.return_value = mock_resp
            mock_openai_cls.return_value = mock_client
            tool._invoke(query="what is AI?")

        tool._retrieve_chunks.assert_called_once()
        results = tool.output("json")
        assert len(results) == 1
        assert results[0]["content"] == "Answer text"
        assert results[0]["url"] == "https://www.perplexity.ai"

    def test_successful_search_with_citations(self, tool):
        citations = ["https://source1.com", "https://source2.com"]
        mock_resp = _mock_openai_response("Answer", citations=citations)
        with patch("agent.tools.perplexity.OpenAI") as mock_openai_cls:
            mock_client = MagicMock()
            mock_client.chat.completions.create.return_value = mock_resp
            mock_openai_cls.return_value = mock_client
            tool._invoke(query="test")

        results = tool.output("json")
        assert len(results) == 2
        assert results[0]["url"] == "https://source1.com"
        assert results[1]["url"] == "https://source2.com"

    def test_model_override(self, tool):
        mock_resp = _mock_openai_response("Response")
        with patch("agent.tools.perplexity.OpenAI") as mock_openai_cls:
            mock_client = MagicMock()
            mock_client.chat.completions.create.return_value = mock_resp
            mock_openai_cls.return_value = mock_client
            tool._invoke(query="test", model="sonar-pro")
        call_kwargs = mock_client.chat.completions.create.call_args.kwargs
        assert call_kwargs["model"] == "sonar-pro"

    def test_api_error_sets_error_output(self, tool):
        tool._param.max_retries = 0
        tool._param.delay_after_error = 0
        with patch("agent.tools.perplexity.OpenAI") as mock_openai_cls:
            mock_client = MagicMock()
            mock_client.chat.completions.create.side_effect = Exception("API error")
            mock_openai_cls.return_value = mock_client
            result = tool._invoke(query="test")
        assert "error" in result.lower()
        assert tool.output("_ERROR") is not None

    def test_openai_client_uses_perplexity_base_url(self, tool):
        mock_resp = _mock_openai_response("ok")
        with patch("agent.tools.perplexity.OpenAI") as mock_openai_cls:
            mock_client = MagicMock()
            mock_client.chat.completions.create.return_value = mock_resp
            mock_openai_cls.return_value = mock_client
            tool._invoke(query="test")
        call_kwargs = mock_openai_cls.call_args.kwargs
        assert call_kwargs["base_url"] == "https://api.perplexity.ai"
        assert call_kwargs["api_key"] == "test-pplx-key"

    def test_thoughts(self, tool):
        tool.get_input = MagicMock(return_value={"query": "my query"})
        assert "my query" in tool.thoughts()
