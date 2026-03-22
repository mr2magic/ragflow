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

from agent.tools.youtubetranscript import YouTubeTranscript, YouTubeTranscriptParam
from test.testcases.test_tools.conftest import make_tool


@pytest.fixture()
def tool(mock_canvas):
    return make_tool(YouTubeTranscript, YouTubeTranscriptParam, mock_canvas, api_key=None)


def _mock_response(text):
    resp = MagicMock()
    resp.raise_for_status = MagicMock()
    resp.text = text
    return resp


class TestYouTubeTranscriptParam:
    def test_defaults(self):
        param = YouTubeTranscriptParam()
        assert param.meta["name"] == "youtube_transcript"

    def test_get_input_form(self):
        form = YouTubeTranscriptParam().get_input_form()
        assert "video" in form


class TestExtractVideoId:
    def test_standard_url(self):
        vid = YouTubeTranscript._extract_video_id("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        assert vid == "dQw4w9WgXcQ"

    def test_short_url(self):
        vid = YouTubeTranscript._extract_video_id("https://youtu.be/dQw4w9WgXcQ")
        assert vid == "dQw4w9WgXcQ"

    def test_embed_url(self):
        vid = YouTubeTranscript._extract_video_id("https://www.youtube.com/embed/dQw4w9WgXcQ")
        assert vid == "dQw4w9WgXcQ"

    def test_shorts_url(self):
        vid = YouTubeTranscript._extract_video_id("https://www.youtube.com/shorts/dQw4w9WgXcQ")
        assert vid == "dQw4w9WgXcQ"

    def test_raw_video_id(self):
        vid = YouTubeTranscript._extract_video_id("dQw4w9WgXcQ")
        assert vid == "dQw4w9WgXcQ"

    def test_unknown_format_returned_as_is(self):
        vid = YouTubeTranscript._extract_video_id("not-a-real-video")
        assert vid == "not-a-real-video"


class TestYouTubeTranscript:
    def test_empty_video_returns_empty(self, tool):
        result = tool._invoke(video="")
        assert result == ""
        assert tool.output("formalized_content") == ""

    def test_successful_transcript_fetch(self, tool):
        transcript = "Hello and welcome to this video..."
        with patch("requests.get", return_value=_mock_response(transcript)):
            tool._invoke(video="dQw4w9WgXcQ")

        tool._retrieve_chunks.assert_called_once()
        results = tool.output("json")
        assert results[0]["content"] == transcript
        assert "dQw4w9WgXcQ" in results[0]["url"]

    def test_jina_url_constructed_from_video_id(self, tool):
        with patch("requests.get", return_value=_mock_response("transcript")) as mock_get:
            tool._invoke(video="dQw4w9WgXcQ")
        called_url = mock_get.call_args.args[0]
        assert "r.jina.ai" in called_url
        assert "dQw4w9WgXcQ" in called_url

    def test_full_url_resolved_to_video_id(self, tool):
        with patch("requests.get", return_value=_mock_response("transcript")) as mock_get:
            tool._invoke(video="https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        called_url = mock_get.call_args.args[0]
        assert "dQw4w9WgXcQ" in called_url

    def test_accept_header_is_text_plain(self, tool):
        with patch("requests.get", return_value=_mock_response("ok")) as mock_get:
            tool._invoke(video="dQw4w9WgXcQ")
        headers = mock_get.call_args.kwargs["headers"]
        assert headers["Accept"] == "text/plain"

    def test_http_error_sets_error_output(self, tool):
        tool._param.max_retries = 0
        tool._param.delay_after_error = 0
        with patch("requests.get", side_effect=requests.HTTPError("403")):
            result = tool._invoke(video="dQw4w9WgXcQ")
        assert "error" in result.lower()
        assert tool.output("_ERROR") is not None

    def test_result_title_includes_video_id(self, tool):
        with patch("requests.get", return_value=_mock_response("content")):
            tool._invoke(video="dQw4w9WgXcQ")
        results = tool.output("json")
        assert "dQw4w9WgXcQ" in results[0]["title"]

    def test_thoughts(self, tool):
        tool.get_input = MagicMock(return_value={"video": "dQw4w9WgXcQ"})
        assert "dQw4w9WgXcQ" in tool.thoughts()
