---
name: langchain_setup
description: Sets up LangChain for LLM applications with RAG pipelines, vector stores, and chain implementations.
model: haiku
---

# LangChain Setup Skill

Configures LLM application environment using LangChain.

## Prerequisites

- Python 3.9+ with virtual environment activated
- OpenAI API key or other LLM provider key

## Workflow

### 1. Install Dependencies

```bash
# Verify virtual environment activation
source .venv/bin/activate

# LangChain core packages
pip install langchain>=0.1.0 langchain-core langchain-community

# LLM Providers
pip install langchain-openai  # OpenAI
# pip install langchain-anthropic  # Anthropic

# Vector Store
pip install chromadb  # Local vector DB
# pip install pinecone-client  # Pinecone
# pip install faiss-cpu  # FAISS

# Document Loaders
pip install pypdf unstructured

# Utilities
pip install python-dotenv tiktoken

# Update requirements.txt
pip freeze > requirements.txt
```

### 2. Project Structure

```bash
mkdir -p src/{chains,agents,tools,vectorstores,loaders}
mkdir -p src/prompts
mkdir -p data/{documents,embeddings}
```

### 3. Environment Variables

**.env:**
```bash
# LLM Providers
OPENAI_API_KEY=sk-...
# ANTHROPIC_API_KEY=sk-ant-...

# Vector Store
CHROMA_PERSIST_DIR=./data/embeddings

# Model Settings
DEFAULT_MODEL=gpt-4-turbo-preview
EMBEDDING_MODEL=text-embedding-3-small
```

### 4. Base Configuration

**src/config.py:**
```python
"""LangChain configuration."""

import os
from dotenv import load_dotenv

load_dotenv()

class Config:
    # LLM
    OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
    DEFAULT_MODEL = os.getenv("DEFAULT_MODEL", "gpt-4-turbo-preview")
    EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "text-embedding-3-small")

    # Vector Store
    CHROMA_PERSIST_DIR = os.getenv("CHROMA_PERSIST_DIR", "./data/embeddings")

    # RAG Settings
    CHUNK_SIZE = 1000
    CHUNK_OVERLAP = 200
    TOP_K_RESULTS = 4

config = Config()
```

### 5. LLM Initialization

**src/llm.py:**
```python
"""LLM initialization and utilities."""

from langchain_openai import ChatOpenAI, OpenAIEmbeddings
from langchain_core.language_models import BaseChatModel
from langchain_core.embeddings import Embeddings

from src.config import config


def get_llm(
    model: str = None,
    temperature: float = 0.7,
    **kwargs
) -> BaseChatModel:
    """Get LLM instance.

    Args:
        model: Model name.
        temperature: Sampling temperature.

    Returns:
        LLM instance.
    """
    return ChatOpenAI(
        model=model or config.DEFAULT_MODEL,
        temperature=temperature,
        **kwargs
    )


def get_embeddings(model: str = None) -> Embeddings:
    """Get embeddings model.

    Args:
        model: Embedding model name.

    Returns:
        Embeddings instance.
    """
    return OpenAIEmbeddings(
        model=model or config.EMBEDDING_MODEL
    )
```

### 6. Vector Store

**src/vectorstores/chroma.py:**
```python
"""ChromaDB vector store utilities."""

from pathlib import Path
from typing import List, Optional

from langchain_chroma import Chroma
from langchain_core.documents import Document
from langchain_core.embeddings import Embeddings

from src.config import config
from src.llm import get_embeddings


def get_vectorstore(
    collection_name: str = "default",
    embeddings: Optional[Embeddings] = None,
    persist_directory: Optional[str] = None
) -> Chroma:
    """Get or create ChromaDB vector store.

    Args:
        collection_name: Name of the collection.
        embeddings: Embeddings model.
        persist_directory: Directory for persistence.

    Returns:
        Chroma vector store.
    """
    persist_dir = persist_directory or config.CHROMA_PERSIST_DIR
    Path(persist_dir).mkdir(parents=True, exist_ok=True)

    return Chroma(
        collection_name=collection_name,
        embedding_function=embeddings or get_embeddings(),
        persist_directory=persist_dir
    )


def add_documents(
    vectorstore: Chroma,
    documents: List[Document]
) -> List[str]:
    """Add documents to vector store.

    Args:
        vectorstore: Vector store instance.
        documents: Documents to add.

    Returns:
        List of document IDs.
    """
    return vectorstore.add_documents(documents)


def similarity_search(
    vectorstore: Chroma,
    query: str,
    k: int = None
) -> List[Document]:
    """Search for similar documents.

    Args:
        vectorstore: Vector store instance.
        query: Search query.
        k: Number of results.

    Returns:
        List of similar documents.
    """
    return vectorstore.similarity_search(
        query,
        k=k or config.TOP_K_RESULTS
    )
```

### 7. Document Loaders

**src/loaders/pdf_loader.py:**
```python
"""PDF document loader with chunking."""

from pathlib import Path
from typing import List

from langchain_community.document_loaders import PyPDFLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_core.documents import Document

from src.config import config


def load_pdf(
    file_path: str,
    chunk_size: int = None,
    chunk_overlap: int = None
) -> List[Document]:
    """Load and chunk PDF document.

    Args:
        file_path: Path to PDF file.
        chunk_size: Size of text chunks.
        chunk_overlap: Overlap between chunks.

    Returns:
        List of document chunks.
    """
    loader = PyPDFLoader(file_path)
    documents = loader.load()

    splitter = RecursiveCharacterTextSplitter(
        chunk_size=chunk_size or config.CHUNK_SIZE,
        chunk_overlap=chunk_overlap or config.CHUNK_OVERLAP,
        length_function=len,
        separators=["\n\n", "\n", " ", ""]
    )

    return splitter.split_documents(documents)


def load_directory(
    directory: str,
    glob_pattern: str = "**/*.pdf"
) -> List[Document]:
    """Load all PDFs from a directory.

    Args:
        directory: Directory path.
        glob_pattern: Pattern to match files.

    Returns:
        List of all document chunks.
    """
    all_docs = []
    for pdf_path in Path(directory).glob(glob_pattern):
        docs = load_pdf(str(pdf_path))
        all_docs.extend(docs)
    return all_docs
```

### 8. RAG Chain

**src/chains/rag_chain.py:**
```python
"""RAG (Retrieval Augmented Generation) chain."""

from typing import Optional

from langchain_core.prompts import ChatPromptTemplate
from langchain_core.output_parsers import StrOutputParser
from langchain_core.runnables import RunnablePassthrough

from src.llm import get_llm
from src.vectorstores.chroma import get_vectorstore


RAG_PROMPT = ChatPromptTemplate.from_messages([
    ("system", """You are a helpful assistant. Answer the question based only on the following context:

{context}

If you cannot find the answer in the context, say "I don't have enough information to answer that question."
"""),
    ("human", "{question}")
])


def create_rag_chain(
    collection_name: str = "default",
    model: Optional[str] = None
):
    """Create a RAG chain.

    Args:
        collection_name: Vector store collection name.
        model: LLM model name.

    Returns:
        RAG chain.
    """
    vectorstore = get_vectorstore(collection_name)
    retriever = vectorstore.as_retriever()
    llm = get_llm(model=model)

    def format_docs(docs):
        return "\n\n".join(doc.page_content for doc in docs)

    chain = (
        {"context": retriever | format_docs, "question": RunnablePassthrough()}
        | RAG_PROMPT
        | llm
        | StrOutputParser()
    )

    return chain


def query_rag(
    question: str,
    collection_name: str = "default",
    model: Optional[str] = None
) -> str:
    """Query the RAG system.

    Args:
        question: User question.
        collection_name: Vector store collection.
        model: LLM model name.

    Returns:
        Generated answer.
    """
    chain = create_rag_chain(collection_name, model)
    return chain.invoke(question)
```

### 9. Prompt Templates

**src/prompts/templates.py:**
```python
"""Reusable prompt templates."""

from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder


# Basic QA
QA_PROMPT = ChatPromptTemplate.from_messages([
    ("system", "You are a helpful assistant."),
    ("human", "{question}")
])

# With chat history
CHAT_PROMPT = ChatPromptTemplate.from_messages([
    ("system", "You are a helpful assistant."),
    MessagesPlaceholder(variable_name="chat_history"),
    ("human", "{question}")
])

# Summarization
SUMMARIZE_PROMPT = ChatPromptTemplate.from_messages([
    ("system", "Summarize the following text concisely:"),
    ("human", "{text}")
])

# Code generation
CODE_PROMPT = ChatPromptTemplate.from_messages([
    ("system", """You are an expert programmer. Generate clean, well-documented code.
Language: {language}
"""),
    ("human", "{task}")
])
```

### 10. Usage Example

**examples/rag_example.py:**
```python
"""Example RAG usage."""

from src.loaders.pdf_loader import load_pdf
from src.vectorstores.chroma import get_vectorstore, add_documents
from src.chains.rag_chain import query_rag


def index_documents(pdf_path: str, collection_name: str = "docs"):
    """Index a PDF document."""
    # Load and chunk
    docs = load_pdf(pdf_path)
    print(f"Loaded {len(docs)} chunks")

    # Add to vector store
    vectorstore = get_vectorstore(collection_name)
    add_documents(vectorstore, docs)
    print("Documents indexed successfully")


def ask_question(question: str, collection_name: str = "docs"):
    """Ask a question about indexed documents."""
    answer = query_rag(question, collection_name)
    print(f"Q: {question}")
    print(f"A: {answer}")
    return answer


if __name__ == "__main__":
    # Index a document
    index_documents("data/documents/sample.pdf", "my-docs")

    # Ask questions
    ask_question("What is the main topic of this document?", "my-docs")
```

## Quick Reference

| Component | Description |
|-----------|-------------|
| `ChatOpenAI` | OpenAI chat model |
| `Chroma` | Vector store |
| `PyPDFLoader` | PDF loader |
| `RecursiveCharacterTextSplitter` | Text chunker |
| `ChatPromptTemplate` | Prompt template |
| `RunnablePassthrough` | Chain composition |

## Generated Structure

```
${PROJECT_NAME}/
├── src/
│   ├── chains/
│   │   └── rag_chain.py
│   ├── vectorstores/
│   │   └── chroma.py
│   ├── loaders/
│   │   └── pdf_loader.py
│   ├── prompts/
│   │   └── templates.py
│   ├── config.py
│   └── llm.py
├── data/
│   ├── documents/
│   └── embeddings/
├── examples/
│   └── rag_example.py
├── .env
└── requirements.txt
```

## Verification Checklist

- [ ] Verify API key configuration
- [ ] Test document loading
- [ ] Test embedding generation
- [ ] Test RAG query

## Summary Report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
LangChain Setup Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

LangChain: 0.1+
Vector Store: ChromaDB
Loaders: PDF

- RAG chain configured
- Vector store setup
- Prompt templates created
- Example included

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
