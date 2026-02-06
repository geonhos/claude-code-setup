---
name: rag_setup
description: Sets up RAG (Retrieval-Augmented Generation) project with ChromaDB, embeddings, and document processing utilities.
model: haiku
---

# RAG Project Setup Skill

Sets up basic RAG project structure and utilities.

## Prerequisites

- Python project already exists
- Virtual environment is activated

## Workflow

### 1. Install Dependencies

```bash
cat >> requirements.txt <<'EOF'

# RAG & Vector DB
chromadb>=0.4.0
sentence-transformers>=2.2.0

# LLM
ollama>=0.1.0
# langchain>=0.1.0  # Optional

# Document Processing
pyyaml>=6.0.0
python-dotenv>=1.0.0

# HTTP Client
httpx>=0.25.0
EOF

pip install -r requirements.txt
```

### 2. Create Directory Structure

```bash
mkdir -p src/{rag,loaders,utils}
mkdir -p data/{documents,chroma_db}
touch src/rag/__init__.py
touch src/loaders/__init__.py
touch src/utils/__init__.py
```

### 3. Configuration File

**src/config.py:**
```python
"""RAG configuration."""

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings."""

    # ChromaDB
    chroma_persist_dir: str = "./data/chroma_db"
    collection_name: str = "documents"

    # Embeddings
    embedding_model: str = "all-MiniLM-L6-v2"

    # Ollama
    ollama_base_url: str = "http://localhost:11434"
    ollama_model: str = "llama2"

    # Retrieval
    top_k: int = 5

    class Config:
        env_file = ".env"


settings = Settings()
```

### 4. ChromaDB Client

**src/rag/vector_store.py:**
```python
"""Vector store using ChromaDB."""

import chromadb
from chromadb.config import Settings as ChromaSettings
from sentence_transformers import SentenceTransformer

from src.config import settings


class VectorStore:
    """ChromaDB vector store wrapper."""

    def __init__(self):
        self.client = chromadb.PersistentClient(
            path=settings.chroma_persist_dir,
            settings=ChromaSettings(anonymized_telemetry=False),
        )
        self.embedding_model = SentenceTransformer(settings.embedding_model)
        self.collection = self._get_or_create_collection()

    def _get_or_create_collection(self):
        """Get or create the collection."""
        return self.client.get_or_create_collection(
            name=settings.collection_name,
            metadata={"hnsw:space": "cosine"},
        )

    def add_documents(
        self,
        documents: list[str],
        metadatas: list[dict] | None = None,
        ids: list[str] | None = None,
    ) -> None:
        """Add documents to the collection."""
        embeddings = self.embedding_model.encode(documents).tolist()

        if ids is None:
            ids = [f"doc_{i}" for i in range(len(documents))]

        self.collection.add(
            documents=documents,
            embeddings=embeddings,
            metadatas=metadatas or [{} for _ in documents],
            ids=ids,
        )

    def search(
        self,
        query: str,
        top_k: int | None = None,
    ) -> list[dict]:
        """Search for similar documents."""
        top_k = top_k or settings.top_k
        query_embedding = self.embedding_model.encode([query]).tolist()

        results = self.collection.query(
            query_embeddings=query_embedding,
            n_results=top_k,
            include=["documents", "metadatas", "distances"],
        )

        return [
            {
                "document": doc,
                "metadata": meta,
                "distance": dist,
            }
            for doc, meta, dist in zip(
                results["documents"][0],
                results["metadatas"][0],
                results["distances"][0],
            )
        ]

    def delete_collection(self) -> None:
        """Delete the collection."""
        self.client.delete_collection(settings.collection_name)

    def count(self) -> int:
        """Get document count."""
        return self.collection.count()
```

### 5. Ollama Client

**src/rag/llm.py:**
```python
"""LLM client using Ollama."""

import httpx

from src.config import settings


class OllamaClient:
    """Ollama LLM client."""

    def __init__(self):
        self.base_url = settings.ollama_base_url
        self.model = settings.ollama_model

    async def generate(
        self,
        prompt: str,
        system: str | None = None,
    ) -> str:
        """Generate response from LLM."""
        messages = []

        if system:
            messages.append({"role": "system", "content": system})

        messages.append({"role": "user", "content": prompt})

        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.base_url}/api/chat",
                json={
                    "model": self.model,
                    "messages": messages,
                    "stream": False,
                },
                timeout=60.0,
            )
            response.raise_for_status()
            return response.json()["message"]["content"]

    def generate_sync(
        self,
        prompt: str,
        system: str | None = None,
    ) -> str:
        """Generate response synchronously."""
        messages = []

        if system:
            messages.append({"role": "system", "content": system})

        messages.append({"role": "user", "content": prompt})

        with httpx.Client() as client:
            response = client.post(
                f"{self.base_url}/api/chat",
                json={
                    "model": self.model,
                    "messages": messages,
                    "stream": False,
                },
                timeout=60.0,
            )
            response.raise_for_status()
            return response.json()["message"]["content"]
```

### 6. RAG Chain

**src/rag/chain.py:**
```python
"""RAG chain combining retrieval and generation."""

from src.rag.vector_store import VectorStore
from src.rag.llm import OllamaClient


class RAGChain:
    """RAG chain for question answering."""

    SYSTEM_PROMPT = """You are a helpful assistant.
Answer the question based on the provided context.
If the context doesn't contain relevant information, say so.

Context:
{context}
"""

    def __init__(self):
        self.vector_store = VectorStore()
        self.llm = OllamaClient()

    def query(self, question: str, top_k: int = 5) -> dict:
        """Query the RAG system."""
        # Retrieve relevant documents
        results = self.vector_store.search(question, top_k=top_k)

        # Build context
        context = "\n\n".join([
            f"[{i+1}] {r['document']}"
            for i, r in enumerate(results)
        ])

        # Generate response
        system = self.SYSTEM_PROMPT.format(context=context)
        response = self.llm.generate_sync(question, system=system)

        return {
            "question": question,
            "answer": response,
            "sources": results,
        }

    async def aquery(self, question: str, top_k: int = 5) -> dict:
        """Query the RAG system asynchronously."""
        results = self.vector_store.search(question, top_k=top_k)

        context = "\n\n".join([
            f"[{i+1}] {r['document']}"
            for i, r in enumerate(results)
        ])

        system = self.SYSTEM_PROMPT.format(context=context)
        response = await self.llm.generate(question, system=system)

        return {
            "question": question,
            "answer": response,
            "sources": results,
        }
```

### 7. Document Loader

**src/loaders/text_loader.py:**
```python
"""Text document loader."""

from pathlib import Path


class TextLoader:
    """Load text documents."""

    def __init__(self, chunk_size: int = 500, chunk_overlap: int = 50):
        self.chunk_size = chunk_size
        self.chunk_overlap = chunk_overlap

    def load(self, file_path: str | Path) -> list[dict]:
        """Load and chunk a text file."""
        path = Path(file_path)
        content = path.read_text(encoding="utf-8")

        chunks = self._split_text(content)

        return [
            {
                "content": chunk,
                "metadata": {
                    "source": str(path),
                    "filename": path.name,
                    "chunk_index": i,
                },
            }
            for i, chunk in enumerate(chunks)
        ]

    def _split_text(self, text: str) -> list[str]:
        """Split text into chunks."""
        chunks = []
        start = 0

        while start < len(text):
            end = start + self.chunk_size
            chunk = text[start:end]

            # Try to break at sentence boundary
            if end < len(text):
                last_period = chunk.rfind(".")
                if last_period > self.chunk_size // 2:
                    end = start + last_period + 1
                    chunk = text[start:end]

            chunks.append(chunk.strip())
            start = end - self.chunk_overlap

        return [c for c in chunks if c]

    def load_directory(self, dir_path: str | Path) -> list[dict]:
        """Load all text files from directory."""
        path = Path(dir_path)
        documents = []

        for file_path in path.glob("**/*.txt"):
            documents.extend(self.load(file_path))

        return documents
```

### 8. Tests

**tests/test_vector_store.py:**
```python
"""Tests for vector store."""

import pytest
from src.rag.vector_store import VectorStore


@pytest.fixture
def vector_store(tmp_path, monkeypatch):
    """Create temporary vector store."""
    monkeypatch.setattr(
        "src.config.settings.chroma_persist_dir",
        str(tmp_path / "chroma")
    )
    return VectorStore()


def test_add_and_search(vector_store):
    """Test adding and searching documents."""
    documents = [
        "Python is a programming language.",
        "FastAPI is a web framework.",
        "ChromaDB is a vector database.",
    ]

    vector_store.add_documents(documents)

    results = vector_store.search("What is Python?", top_k=1)

    assert len(results) == 1
    assert "Python" in results[0]["document"]


def test_count(vector_store):
    """Test document count."""
    documents = ["Doc 1", "Doc 2", "Doc 3"]
    vector_store.add_documents(documents)

    assert vector_store.count() == 3
```

### 9. CLI Interface (Optional)

**src/cli.py:**
```python
"""CLI for RAG system."""

import click

from src.rag.chain import RAGChain
from src.rag.vector_store import VectorStore
from src.loaders.text_loader import TextLoader


@click.group()
def cli():
    """RAG CLI."""
    pass


@cli.command()
@click.argument("directory")
def index(directory: str):
    """Index documents from directory."""
    loader = TextLoader()
    store = VectorStore()

    documents = loader.load_directory(directory)

    store.add_documents(
        documents=[d["content"] for d in documents],
        metadatas=[d["metadata"] for d in documents],
    )

    click.echo(f"Indexed {len(documents)} documents")


@cli.command()
@click.argument("question")
def query(question: str):
    """Query the RAG system."""
    chain = RAGChain()
    result = chain.query(question)

    click.echo(f"\nAnswer: {result['answer']}\n")
    click.echo("Sources:")
    for i, source in enumerate(result["sources"]):
        click.echo(f"  [{i+1}] {source['metadata'].get('filename', 'unknown')}")


if __name__ == "__main__":
    cli()
```

### 10. Update .env

```bash
cat >> .env <<'EOF'

# ChromaDB
CHROMA_PERSIST_DIR=./data/chroma_db
COLLECTION_NAME=documents

# Embeddings
EMBEDDING_MODEL=all-MiniLM-L6-v2

# Ollama
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_MODEL=llama2

# Retrieval
TOP_K=5
EOF
```

### 11. Commit

```bash
git add .
git commit -m "[Phase 0] Setup RAG infrastructure

RAG Components:
- ChromaDB vector store with sentence-transformers
- Ollama LLM client (sync and async)
- RAG chain combining retrieval and generation

Document Processing:
- Text loader with chunking
- Directory indexing support

Testing:
- Vector store tests with temporary DB
"
```

## Generated Structure

```
project/
├── src/
│   ├── config.py
│   ├── cli.py
│   ├── rag/
│   │   ├── __init__.py
│   │   ├── vector_store.py   # ChromaDB wrapper
│   │   ├── llm.py            # Ollama client
│   │   └── chain.py          # RAG chain
│   ├── loaders/
│   │   ├── __init__.py
│   │   └── text_loader.py    # Document loader
│   └── utils/
│       └── __init__.py
├── data/
│   ├── documents/            # Original documents
│   └── chroma_db/            # Vector DB
└── tests/
    └── test_vector_store.py
```

## Usage Example

```python
# Index documents
from src.loaders.text_loader import TextLoader
from src.rag.vector_store import VectorStore

loader = TextLoader()
store = VectorStore()

docs = loader.load_directory("./data/documents")
store.add_documents(
    documents=[d["content"] for d in docs],
    metadatas=[d["metadata"] for d in docs],
)

# Query
from src.rag.chain import RAGChain

chain = RAGChain()
result = chain.query("What is Python?")
print(result["answer"])
```

## Notes

- **Ollama required**: Ollama server must be running for LLM usage
- **First run**: Embedding model download takes time
- **Memory**: Batch processing recommended for large documents
