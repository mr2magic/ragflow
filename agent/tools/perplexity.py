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

from openai import OpenAI

from agent.tools.base import ToolParamBase, ToolBase, ToolMeta
from common.connection_utils import timeout


class PerplexitySearchParam(ToolParamBase):
    """
    Define the Perplexity Search component parameters.
    """

    def __init__(self):
        self.meta: ToolMeta = {
            "name": "perplexity_search",
            "description": """
Perplexity is an AI-powered search engine that provides accurate, concise answers with cited sources.
Use it for:
   - Questions requiring up-to-date information
   - Research queries needing synthesized answers
   - Factual lookups with source attribution
            """,
            "parameters": {
                "query": {
                    "type": "string",
                    "description": "The search query to send to Perplexity.",
                    "default": "{sys.query}",
                    "required": True,
                },
                "model": {
                    "type": "string",
                    "description": "Perplexity model to use. Default: sonar.",
                    "enum": ["sonar", "sonar-pro", "sonar-reasoning", "sonar-reasoning-pro"],
                    "default": "sonar",
                    "required": False,
                },
            },
        }
        super().__init__()
        self.api_key = os.environ.get("PERPLEXITY_API_KEY", "")
        self.model = "sonar"

    def check(self):
        self.check_empty(self.api_key, "Perplexity API key")

    def get_input_form(self) -> dict[str, dict]:
        return {
            "query": {
                "name": "Query",
                "type": "line",
            }
        }


class PerplexitySearch(ToolBase, ABC):
    component_name = "PerplexitySearch"

    @timeout(int(os.environ.get("COMPONENT_EXEC_TIMEOUT", 30)))
    def _invoke(self, **kwargs):
        if self.check_if_canceled("PerplexitySearch processing"):
            return

        query = kwargs.get("query", "")
        if not query:
            self.set_output("formalized_content", "")
            return ""

        client = OpenAI(
            api_key=self._param.api_key,
            base_url="https://api.perplexity.ai",
        )
        model = kwargs.get("model", self._param.model)

        last_e = None
        for _ in range(self._param.max_retries + 1):
            if self.check_if_canceled("PerplexitySearch processing"):
                return

            try:
                response = client.chat.completions.create(
                    model=model,
                    messages=[{"role": "user", "content": query}],
                )
                if self.check_if_canceled("PerplexitySearch processing"):
                    return

                content = response.choices[0].message.content
                citations = getattr(response, "citations", []) or []

                results = [{"title": f"Perplexity: {query}", "url": url, "content": content}
                           for url in (citations or ["https://www.perplexity.ai"])]
                if not results:
                    results = [{"title": f"Perplexity: {query}", "url": "https://www.perplexity.ai", "content": content}]

                self._retrieve_chunks(
                    results,
                    get_title=lambda r: r["title"],
                    get_url=lambda r: r["url"],
                    get_content=lambda r: r["content"],
                )
                self.set_output("json", results)
                return self.output("formalized_content")
            except Exception as e:
                if self.check_if_canceled("PerplexitySearch processing"):
                    return

                last_e = e
                logging.exception(f"Perplexity error: {e}")
                time.sleep(self._param.delay_after_error)

        if last_e:
            self.set_output("_ERROR", str(last_e))
            return f"Perplexity error: {last_e}"

        assert False, self.output()

    def thoughts(self) -> str:
        return "Keywords: {}\nSearching with Perplexity AI...".format(
            self.get_input().get("query", "-_-!")
        )
