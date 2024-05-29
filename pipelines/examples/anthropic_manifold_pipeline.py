"""
title: Anthropic Pipeline
author: justinh-rahb
date: 2024-05-27
version: 1.0
license: MIT
description: A pipeline for generating text using the Anthropic API.
dependencies: requests, anthropic
environment_variables: ANTHROPIC_API_KEY
"""

import os
from anthropic import Anthropic, RateLimitError, APIStatusError, APIConnectionError

from schemas import OpenAIChatMessage
from typing import List, Union, Generator, Iterator
from pydantic import BaseModel
import requests


class Pipeline:
    def __init__(self):
        self.type = "manifold"
        self.id = "anthropic"
        self.name = "Anthropic/"

        class Valves(BaseModel):
            ANTHROPIC_API_KEY: str

        self.valves = Valves(**{"ANTHROPIC_API_KEY": os.getenv("ANTHROPIC_API_KEY")})
        self.client = Anthropic(api_key=self.valves.ANTHROPIC_API_KEY)

    def get_anthropic_models(self):
        # In the future, this could fetch models dynamically from Anthropic
        return [
            {"id": "claude-3-haiku-20240307", "name": "claude-3-haiku"},
            {"id": "claude-3-opus-20240229", "name": "claude-3-opus"},
            {"id": "claude-3-sonnet-20240229", "name": "claude-3-sonnet"},
            # Add other Anthropic models here as they become available
        ]

    async def on_startup(self):
        print(f"on_startup:{__name__}")
        pass

    async def on_shutdown(self):
        print(f"on_shutdown:{__name__}")
        pass

    async def on_valves_update(self):
        self.client = Anthropic(api_key=self.valves.ANTHROPIC_API_KEY)
        pass

    # Pipelines are the models that are available in the manifold.
    # It can be a list or a function that returns a list.
    def pipelines(self) -> List[dict]:
        return self.get_anthropic_models()

    def pipe(
        self, user_message: str, model_id: str, messages: List[dict], body: dict
    ) -> Union[str, Generator, Iterator]:
        try:
            if body.get("stream", False):
                return self.stream_response(model_id, messages, body)
            else:
                return self.get_completion(model_id, messages, body)
        except (RateLimitError, APIStatusError, APIConnectionError) as e:
            return f"Error: {e}"

    def stream_response(
        self, model_id: str, messages: List[dict], body: dict
    ) -> Generator:
        stream = self.client.messages.create(
            model=model_id,
            messages=messages,
            max_tokens=body.get("max_tokens", 1024),
            temperature=body.get("temperature", 1.0),
            top_k=body.get("top_k", 40),
            top_p=body.get("top_p", 0.9),
            stop_sequences=body.get("stop", []),
            stream=True,
        )

        for chunk in stream:
            if chunk.type == "content_block_start":
                yield chunk.content_block.text
            elif chunk.type == "content_block_delta":
                yield chunk.delta.text

    def get_completion(self, model_id: str, messages: List[dict], body: dict) -> str:
        response = self.client.messages.create(
            model=model_id,
            messages=messages,
            max_tokens=body.get("max_tokens", 1024),
            temperature=body.get("temperature", 1.0),
            top_k=body.get("top_k", 40),
            top_p=body.get("top_p", 0.9),
            stop_sequences=body.get("stop", []),
        )
        return response.content[0].text