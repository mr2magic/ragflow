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
import time
from abc import ABC

import requests

from agent.tools.base import ToolParamBase, ToolBase, ToolMeta
from common.connection_utils import timeout


class JinaReaderParam(ToolParamBase):
    """
    Define the Jina Reader component parameters.
    Extracts clean, LLM-friendly content from any URL via r.jina.ai.
    No API key required for basic use.
    """

    def __init__(self):
        self.meta: ToolMeta = {
            "name": "jina_reader",
            "description": """
Extract clean, readable content from any URL using Jina Reader (r.jina.ai).
Works on web pages, articles, PDFs, and YouTube videos.
Use it when you need the full content of a specific URL rather than search snippets.
            """,
            "parameters": {
                "url": {
                    "type": "string",
                    "description": "The URL to extract content from.",
                    "default": "",
                    "required": True,
                },
            },
        }
        super().__init__()
        self.api_key = os.environ.get("JINA_API_KEY", "")

    def check(self):
        pass  # No API key required for basic use

    def get_input_form(self) -> dict[str, dict]:
        return {
            "url": {
                "name": "URL",
                "type": "line",
            }
        }


class JinaReader(ToolBase, ABC):
    component_name = "JinaReader"

    _BASE_URL = "https://r.jina.ai/"

    @timeout(int(os.environ.get("COMPONENT_EXEC_TIMEOUT", 30)))
    def _invoke(self, **kwargs):
        if self.check_if_canceled("JinaReader processing"):
            return

        url = kwargs.get("url", "")
        if not url:
            self.set_output("formalized_content", "")
            return ""

        headers = {"Accept": "text/plain"}
        if self._param.api_key:
            headers["Authorization"] = f"Bearer {self._param.api_key}"

        jina_url = self._BASE_URL + url.lstrip("/")

        last_e = None
        for _ in range(self._param.max_retries + 1):
            if self.check_if_canceled("JinaReader processing"):
                return

            try:
                resp = requests.get(jina_url, headers=headers, timeout=30)
                resp.raise_for_status()
                content = resp.text

                if self.check_if_canceled("JinaReader processing"):
                    return

                results = [{"title": url, "url": url, "content": content}]
                self._retrieve_chunks(
                    results,
                    get_title=lambda r: r["title"],
                    get_url=lambda r: r["url"],
                    get_content=lambda r: r["content"],
                )
                self.set_output("json", results)
                return self.output("formalized_content")
            except Exception as e:
                if self.check_if_canceled("JinaReader processing"):
                    return

                last_e = e
                logging.exception(f"JinaReader error: {e}")
                time.sleep(self._param.delay_after_error)

        if last_e:
            self.set_output("_ERROR", str(last_e))
            return f"JinaReader error: {last_e}"

        assert False, self.output()

    def thoughts(self) -> str:
        return "Reading content from {}...".format(self.get_input().get("url", "-_-!"))
