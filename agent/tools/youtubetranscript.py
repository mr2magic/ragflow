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
import logging
import os
import re
import time
from abc import ABC

import requests

from agent.tools.base import ToolParamBase, ToolBase, ToolMeta
from common.connection_utils import timeout


class YouTubeTranscriptParam(ToolParamBase):
    """
    Define the YouTube Transcript component parameters.
    Fetches transcripts from YouTube videos without an API key using Jina Reader.
    """

    def __init__(self):
        self.meta: ToolMeta = {
            "name": "youtube_transcript",
            "description": """
Fetch the transcript/subtitles from a YouTube video.
Accepts full YouTube URLs or video IDs.
Use it to extract spoken content from YouTube videos for summarization, Q&A, or analysis.
            """,
            "parameters": {
                "video": {
                    "type": "string",
                    "description": "YouTube video URL (e.g. https://www.youtube.com/watch?v=abc123) or video ID (e.g. abc123).",
                    "default": "",
                    "required": True,
                },
            },
        }
        super().__init__()

    def check(self):
        pass  # No API key required

    def get_input_form(self) -> dict[str, dict]:
        return {
            "video": {
                "name": "YouTube URL or Video ID",
                "type": "line",
            }
        }


class YouTubeTranscript(ToolBase, ABC):
    component_name = "YouTubeTranscript"

    @staticmethod
    def _extract_video_id(video: str) -> str:
        """Extract YouTube video ID from URL or return as-is if already an ID."""
        patterns = [
            r"(?:v=|youtu\.be/|embed/|shorts/)([A-Za-z0-9_-]{11})",
        ]
        for pattern in patterns:
            match = re.search(pattern, video)
            if match:
                return match.group(1)
        # Assume it's already a video ID if 11 chars
        if re.match(r"^[A-Za-z0-9_-]{11}$", video):
            return video
        return video

    @timeout(int(os.environ.get("COMPONENT_EXEC_TIMEOUT", 30)))
    def _invoke(self, **kwargs):
        if self.check_if_canceled("YouTubeTranscript processing"):
            return

        video = kwargs.get("video", "")
        if not video:
            self.set_output("formalized_content", "")
            return ""

        video_id = self._extract_video_id(video)
        video_url = f"https://www.youtube.com/watch?v={video_id}"
        jina_url = f"https://r.jina.ai/{video_url}"

        last_e = None
        for _ in range(self._param.max_retries + 1):
            if self.check_if_canceled("YouTubeTranscript processing"):
                return

            try:
                resp = requests.get(jina_url, headers={"Accept": "text/plain"}, timeout=30)
                resp.raise_for_status()
                content = resp.text

                if self.check_if_canceled("YouTubeTranscript processing"):
                    return

                results = [{"title": f"YouTube: {video_id}", "url": video_url, "content": content}]
                self._retrieve_chunks(
                    results,
                    get_title=lambda r: r["title"],
                    get_url=lambda r: r["url"],
                    get_content=lambda r: r["content"],
                )
                self.set_output("json", results)
                return self.output("formalized_content")
            except Exception as e:
                if self.check_if_canceled("YouTubeTranscript processing"):
                    return

                last_e = e
                logging.exception(f"YouTubeTranscript error: {e}")
                time.sleep(self._param.delay_after_error)

        if last_e:
            self.set_output("_ERROR", str(last_e))
            return f"YouTubeTranscript error: {last_e}"

        assert False, self.output()

    def thoughts(self) -> str:
        return "Fetching transcript for {}...".format(self.get_input().get("video", "-_-!"))
