# SCRAINEE Knowledge System - Implementierungsplan

> Dieses Dokument beschreibt die geplante Erweiterung von SCRAINEE um ein intelligentes Offline-Wissenssystem mit semantischer Suche.

## Status

- [x] Phase 1: QuickAsk-Fix (abgeschlossen 2026-01-17)
- [ ] Phase 2: Lokales Ollama auf Mac
- [ ] Phase 3: Windows Knowledge-Server Setup
- [ ] Phase 4: MCP-Integration in SCRAINEE
- [ ] Phase 5: Document Processing
- [ ] Phase 6: Advanced Features

---

## Architektur-Uebersicht

```
+------------------------------------------+
|         macOS: SCRAINEE App              |
|  (Screenshot-Capture, UI, QuickAsk)      |
+------------------------------------------+
              |  MCP / REST API
              v
+------------------------------------------+
|     Windows-Server: Knowledge-Hub        |
|  (Ollama, Qdrant, Document-Processing)   |
+------------------------------------------+
              |
    +---------+---------+
    |         |         |
    v         v         v
+-------+ +-------+ +----------+
|Ollama | |Qdrant | |Document  |
|(LLM)  | |(Vector)| |Processor |
+-------+ +-------+ +----------+
```

### Entscheidungen
- **Ollama:** Optional mit Claude als Fallback
- **Dateitypen:** Office-Dokumente (PowerPoint, PDF, Excel, CSV)
- **Scale:** 300-400GB Daten
- **Architektur:** Dedizierter Windows-Service mit MCP-Kommunikation

---

## Phase 2: Lokales Ollama auf Mac

### Ziel
Schnelle lokale Anfragen ohne Cloud-Abhaengigkeit als optionale Erweiterung.

### Installation
```bash
# Ollama installieren
brew install ollama

# Service starten
brew services start ollama

# Modelle laden
ollama pull mistral
ollama pull nomic-embed-text
```

### OllamaClient.swift erstellen

```swift
// Scrainee/Core/AI/OllamaClient.swift

import Foundation

/// Client fuer lokale Ollama-Instanz
actor OllamaClient {
    static let shared = OllamaClient()

    private let baseURL = URL(string: "http://localhost:11434/api")!
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)
    }

    var isAvailable: Bool {
        get async {
            do {
                let url = URL(string: "http://localhost:11434/api/tags")!
                let (_, response) = try await session.data(from: url)
                return (response as? HTTPURLResponse)?.statusCode == 200
            } catch {
                return false
            }
        }
    }

    // MARK: - Text Generation

    func generate(prompt: String, model: String = "mistral") async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false
        ]

        var request = URLRequest(url: baseURL.appendingPathComponent("generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        return response.response
    }

    // MARK: - Embeddings

    func embed(text: String, model: String = "nomic-embed-text") async throws -> [Float] {
        let body: [String: Any] = [
            "model": model,
            "input": text
        ]

        var request = URLRequest(url: baseURL.appendingPathComponent("embed"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(OllamaEmbedResponse.self, from: data)
        return response.embeddings.first ?? []
    }

    // MARK: - Specialized Operations

    func summarize(_ content: String) async throws -> String {
        let prompt = """
        Fasse den folgenden Text kurz zusammen (max 3 Saetze):

        \(content.prefix(4000))
        """
        return try await generate(prompt: prompt)
    }

    func extractTags(_ content: String) async throws -> [String] {
        let prompt = """
        Extrahiere 3-5 relevante Tags aus diesem Inhalt.
        Antworte NUR mit einer kommaseparierten Liste.

        \(content.prefix(2000))
        """
        let response = try await generate(prompt: prompt)
        return response.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

// MARK: - Response Types

struct OllamaGenerateResponse: Codable {
    let model: String
    let response: String
    let done: Bool
}

struct OllamaEmbedResponse: Codable {
    let model: String
    let embeddings: [[Float]]
}

enum OllamaError: LocalizedError {
    case notAvailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Ollama ist nicht verfuegbar. Bitte starte den Service."
        case .invalidResponse:
            return "Ungueltige Antwort von Ollama"
        }
    }
}
```

### Settings UI erweitern

```swift
// In SettingsView.swift hinzufuegen:

Section("Offline-LLM (Ollama)") {
    Toggle("Ollama verwenden", isOn: $appState.useOllama)

    HStack {
        Text("Status:")
        if ollamaAvailable {
            Label("Verbunden", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
        } else {
            Label("Nicht verfuegbar", systemImage: "xmark.circle.fill")
                .foregroundColor(.red)
        }
    }

    Button("Ollama installieren...") {
        NSWorkspace.shared.open(URL(string: "https://ollama.com")!)
    }
}
```

---

## Phase 3: Windows Knowledge-Server Setup

### Voraussetzungen

**Hardware:**
- CPU: 8+ Cores
- RAM: 32GB+
- GPU: NVIDIA RTX 3060+ (fuer schnelle Embeddings)
- Storage: SSD, 500GB+

**Software:**
- Windows 10/11 oder Windows Server
- Docker Desktop mit WSL2
- NVIDIA Container Toolkit
- Python 3.10+

### Docker Compose Setup

```yaml
# docker-compose.yml
version: '3.8'

services:
  qdrant:
    image: qdrant/qdrant:latest
    container_name: knowledge-qdrant
    ports:
      - "6333:6333"
      - "6334:6334"
    volumes:
      - ./data/qdrant:/qdrant/storage
    environment:
      - QDRANT__STORAGE__STORAGE_PATH=/qdrant/storage
    restart: unless-stopped

  ollama:
    image: ollama/ollama:latest
    container_name: knowledge-ollama
    ports:
      - "11434:11434"
    volumes:
      - ./data/ollama:/root/.ollama
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    restart: unless-stopped

  mcp-server:
    build: ./mcp_server
    container_name: knowledge-mcp
    ports:
      - "8080:8080"
    depends_on:
      - qdrant
      - ollama
    environment:
      - QDRANT_HOST=qdrant
      - OLLAMA_HOST=ollama
    volumes:
      - ./data/watched:/watched:ro
    restart: unless-stopped
```

### Qdrant Konfiguration fuer grosse Datenmengen

```yaml
# qdrant_config.yaml
storage:
  storage_path: /qdrant/storage
  optimizers:
    memmap_threshold_kb: 20000
    indexing_threshold_kb: 10000

  hnsw_index:
    m: 16
    ef_construct: 100
    on_disk: true  # Disk-basierter Index fuer grosse Daten

service:
  max_request_size_mb: 32
```

---

## Phase 4: MCP Server Implementation

### Python MCP Server

```python
# mcp_server/main.py
from fastmcp import FastMCP
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, PointStruct
import httpx
import os

mcp = FastMCP("SCRAINEE Knowledge Hub")

# Clients
qdrant = QdrantClient(host=os.getenv("QDRANT_HOST", "localhost"), port=6333)
ollama_url = f"http://{os.getenv('OLLAMA_HOST', 'localhost')}:11434/api"

COLLECTION_NAME = "knowledge"
EMBEDDING_DIM = 768  # nomic-embed-text

# Ensure collection exists
def ensure_collection():
    collections = qdrant.get_collections().collections
    if not any(c.name == COLLECTION_NAME for c in collections):
        qdrant.create_collection(
            collection_name=COLLECTION_NAME,
            vectors_config=VectorParams(size=EMBEDDING_DIM, distance=Distance.COSINE)
        )

ensure_collection()

async def generate_embedding(text: str) -> list[float]:
    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{ollama_url}/embed",
            json={"model": "nomic-embed-text", "input": text},
            timeout=60.0
        )
        data = response.json()
        return data["embeddings"][0]

async def generate_text(prompt: str) -> str:
    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{ollama_url}/generate",
            json={"model": "mistral", "prompt": prompt, "stream": False},
            timeout=120.0
        )
        data = response.json()
        return data["response"]

@mcp.tool()
async def semantic_search(query: str, limit: int = 10, project: str = None) -> list:
    """Semantische Suche in der Wissensdatenbank"""
    embedding = await generate_embedding(query)

    filter_condition = None
    if project:
        filter_condition = {"must": [{"key": "project", "match": {"value": project}}]}

    results = qdrant.search(
        collection_name=COLLECTION_NAME,
        query_vector=embedding,
        limit=limit,
        query_filter=filter_condition
    )

    return [
        {
            "content": hit.payload.get("content", ""),
            "source": hit.payload.get("source", ""),
            "project": hit.payload.get("project", ""),
            "score": hit.score,
            "metadata": hit.payload.get("metadata", {})
        }
        for hit in results
    ]

@mcp.tool()
async def ask_knowledge(question: str, project: str = None, context_limit: int = 5) -> str:
    """Beantwortet Fragen basierend auf der Wissensdatenbank"""
    context = await semantic_search(question, limit=context_limit, project=project)

    if not context:
        return "Keine relevanten Informationen gefunden."

    context_text = "\n\n".join([
        f"[{c['source']}]: {c['content'][:500]}"
        for c in context
    ])

    prompt = f"""Basierend auf folgendem Kontext, beantworte die Frage praezise.

Kontext:
{context_text}

Frage: {question}

Antwort auf Deutsch:"""

    return await generate_text(prompt)

@mcp.tool()
async def index_document(
    content: str,
    source: str,
    project: str = None,
    metadata: dict = None
) -> dict:
    """Indexiert einen Text in der Wissensdatenbank"""
    import hashlib
    import time

    # Chunking fuer lange Dokumente
    chunks = chunk_text(content, chunk_size=500, overlap=50)

    points = []
    for i, chunk in enumerate(chunks):
        embedding = await generate_embedding(chunk)
        point_id = hashlib.md5(f"{source}_{i}".encode()).hexdigest()

        points.append(PointStruct(
            id=point_id,
            vector=embedding,
            payload={
                "content": chunk,
                "source": source,
                "project": project or "default",
                "chunk_index": i,
                "total_chunks": len(chunks),
                "metadata": metadata or {},
                "indexed_at": time.time()
            }
        ))

    qdrant.upsert(collection_name=COLLECTION_NAME, points=points)

    return {
        "status": "success",
        "chunks_indexed": len(chunks),
        "source": source
    }

@mcp.tool()
async def list_projects() -> list:
    """Listet alle Projekte in der Wissensdatenbank"""
    # Scroll durch alle Punkte und sammle unique projects
    projects = set()
    offset = None

    while True:
        results, offset = qdrant.scroll(
            collection_name=COLLECTION_NAME,
            limit=100,
            offset=offset,
            with_payload=["project"]
        )
        for point in results:
            if point.payload and "project" in point.payload:
                projects.add(point.payload["project"])
        if offset is None:
            break

    return list(projects)

@mcp.tool()
async def get_project_summary(project_name: str) -> str:
    """Generiert eine Zusammenfassung eines Projekts"""
    # Hole repraesentative Chunks
    results = await semantic_search(
        query=f"Wichtigste Informationen ueber {project_name}",
        limit=10,
        project=project_name
    )

    if not results:
        return f"Keine Informationen zu Projekt '{project_name}' gefunden."

    content = "\n".join([r["content"] for r in results])

    prompt = f"""Erstelle eine kurze Zusammenfassung (3-5 Saetze) des Projekts '{project_name}' basierend auf folgenden Informationen:

{content[:3000]}

Zusammenfassung:"""

    return await generate_text(prompt)

@mcp.resource("knowledge://stats")
async def get_stats() -> dict:
    """Statistiken der Wissensdatenbank"""
    collection_info = qdrant.get_collection(COLLECTION_NAME)
    projects = await list_projects()

    return {
        "total_vectors": collection_info.points_count,
        "projects": projects,
        "projects_count": len(projects),
        "collection_status": collection_info.status.name
    }

def chunk_text(text: str, chunk_size: int = 500, overlap: int = 50) -> list[str]:
    """Teilt Text in Chunks mit Ueberlappung"""
    words = text.split()
    chunks = []
    start = 0

    while start < len(words):
        end = start + chunk_size
        chunk = " ".join(words[start:end])
        chunks.append(chunk)
        start = end - overlap

    return chunks

if __name__ == "__main__":
    mcp.run(transport="stdio")
```

### Dockerfile fuer MCP Server

```dockerfile
# mcp_server/Dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8080

CMD ["python", "main.py"]
```

```txt
# mcp_server/requirements.txt
fastmcp>=0.1.0
qdrant-client>=1.7.0
httpx>=0.25.0
```

---

## Phase 5: Document Processing Pipeline

### Document Processor

```python
# mcp_server/document_processor.py
from unstructured.partition.auto import partition
from pathlib import Path
import hashlib
import asyncio

SUPPORTED_TYPES = {
    '.pdf': 'pdf',
    '.pptx': 'pptx', '.ppt': 'ppt',
    '.xlsx': 'xlsx', '.xls': 'xls',
    '.csv': 'csv',
    '.docx': 'docx', '.doc': 'doc',
    '.txt': 'text',
    '.md': 'markdown'
}

class DocumentProcessor:
    def __init__(self, mcp_client):
        self.mcp = mcp_client

    async def process_file(self, file_path: str, project: str = None) -> dict:
        path = Path(file_path)

        if path.suffix.lower() not in SUPPORTED_TYPES:
            return {"status": "skipped", "reason": "unsupported_type"}

        # Text extrahieren
        elements = partition(filename=str(path))
        text_content = "\n".join([str(el) for el in elements])

        if not text_content.strip():
            return {"status": "skipped", "reason": "empty_content"}

        # Metadata sammeln
        metadata = {
            "filename": path.name,
            "file_type": path.suffix.lower(),
            "file_size": path.stat().st_size,
            "modified": path.stat().st_mtime
        }

        # Indexieren
        result = await self.mcp.index_document(
            content=text_content,
            source=str(path),
            project=project or path.parent.name,
            metadata=metadata
        )

        return result

    async def process_directory(self, directory: str, project: str = None) -> dict:
        path = Path(directory)
        results = {"processed": 0, "skipped": 0, "errors": 0}

        for file_path in path.rglob("*"):
            if file_path.is_file() and file_path.suffix.lower() in SUPPORTED_TYPES:
                try:
                    result = await self.process_file(str(file_path), project)
                    if result.get("status") == "success":
                        results["processed"] += 1
                    else:
                        results["skipped"] += 1
                except Exception as e:
                    print(f"Error processing {file_path}: {e}")
                    results["errors"] += 1

        return results
```

### File Watcher Service

```python
# mcp_server/file_watcher.py
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
import asyncio
from pathlib import Path

class DocumentEventHandler(FileSystemEventHandler):
    def __init__(self, processor, project_name):
        self.processor = processor
        self.project_name = project_name
        self.pending_files = {}
        self.debounce_seconds = 2

    def on_modified(self, event):
        if event.is_directory:
            return
        self._schedule_processing(event.src_path)

    def on_created(self, event):
        if event.is_directory:
            return
        self._schedule_processing(event.src_path)

    def _schedule_processing(self, file_path):
        # Debouncing: Warte bis Datei stabil ist
        self.pending_files[file_path] = asyncio.get_event_loop().time()
        asyncio.create_task(self._process_after_delay(file_path))

    async def _process_after_delay(self, file_path):
        await asyncio.sleep(self.debounce_seconds)

        if file_path in self.pending_files:
            del self.pending_files[file_path]
            try:
                result = await self.processor.process_file(file_path, self.project_name)
                print(f"Processed: {file_path} -> {result}")
            except Exception as e:
                print(f"Error processing {file_path}: {e}")

class ProjectWatcher:
    def __init__(self, processor):
        self.processor = processor
        self.observers = {}

    def watch(self, directory: str, project_name: str):
        if directory in self.observers:
            return

        event_handler = DocumentEventHandler(self.processor, project_name)
        observer = Observer()
        observer.schedule(event_handler, directory, recursive=True)
        observer.start()
        self.observers[directory] = observer
        print(f"Watching: {directory} as project '{project_name}'")

    def stop(self, directory: str = None):
        if directory:
            if directory in self.observers:
                self.observers[directory].stop()
                del self.observers[directory]
        else:
            for obs in self.observers.values():
                obs.stop()
            self.observers.clear()
```

---

## Phase 6: SCRAINEE Swift Integration

### KnowledgeHubClient.swift

```swift
// Scrainee/Core/Integration/KnowledgeHubClient.swift

import Foundation

actor KnowledgeHubClient {
    static let shared = KnowledgeHubClient()

    private var serverAddress: String {
        UserDefaults.standard.string(forKey: "knowledgeHubAddress") ?? "localhost:8080"
    }

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    var isConnected: Bool {
        get async {
            do {
                let stats = try await getStats()
                return true
            } catch {
                return false
            }
        }
    }

    // MARK: - API Calls

    func semanticSearch(query: String, limit: Int = 10, project: String? = nil) async throws -> [KnowledgeMatch] {
        var params: [String: Any] = ["query": query, "limit": limit]
        if let project = project {
            params["project"] = project
        }

        let data = try await callTool("semantic_search", arguments: params)
        return try JSONDecoder().decode([KnowledgeMatch].self, from: data)
    }

    func askKnowledge(question: String, project: String? = nil) async throws -> String {
        var params: [String: Any] = ["question": question]
        if let project = project {
            params["project"] = project
        }

        let data = try await callTool("ask_knowledge", arguments: params)
        let response = try JSONDecoder().decode(StringResponse.self, from: data)
        return response.result
    }

    func listProjects() async throws -> [String] {
        let data = try await callTool("list_projects", arguments: [:])
        return try JSONDecoder().decode([String].self, from: data)
    }

    func getProjectSummary(project: String) async throws -> String {
        let data = try await callTool("get_project_summary", arguments: ["project_name": project])
        let response = try JSONDecoder().decode(StringResponse.self, from: data)
        return response.result
    }

    func getStats() async throws -> KnowledgeStats {
        let url = URL(string: "http://\(serverAddress)/resource/knowledge://stats")!
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(KnowledgeStats.self, from: data)
    }

    // MARK: - Private

    private func callTool(_ name: String, arguments: [String: Any]) async throws -> Data {
        let url = URL(string: "http://\(serverAddress)/tool/\(name)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: arguments)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw KnowledgeHubError.requestFailed
        }

        return data
    }
}

// MARK: - Models

struct KnowledgeMatch: Codable {
    let content: String
    let source: String
    let project: String?
    let score: Double
    let metadata: [String: String]?
}

struct KnowledgeStats: Codable {
    let totalVectors: Int
    let projects: [String]
    let projectsCount: Int
    let collectionStatus: String

    enum CodingKeys: String, CodingKey {
        case totalVectors = "total_vectors"
        case projects
        case projectsCount = "projects_count"
        case collectionStatus = "collection_status"
    }
}

struct StringResponse: Codable {
    let result: String
}

enum KnowledgeHubError: LocalizedError {
    case notConnected
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Knowledge Hub nicht verbunden"
        case .requestFailed:
            return "Anfrage fehlgeschlagen"
        }
    }
}
```

---

## Netzwerk-Setup

### Option A: Lokales Netzwerk
- Windows-PC mit statischer IP (z.B. 192.168.1.100)
- Ports freigeben: 6333, 11434, 8080
- In SCRAINEE Settings: `192.168.1.100:8080`

### Option B: Tailscale (empfohlen fuer Remote)
```bash
# Auf beiden Geraeten
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up

# Dann erreichbar ueber: windows-pc.tailnet-xxxx.ts.net:8080
```

---

## Geschaetzte Ressourcen (300-400GB Daten)

| Komponente | Speicher | RAM |
|------------|----------|-----|
| Qdrant Index | 300-500MB | 2-4GB |
| Ollama Models | 4-8GB | 8-16GB |
| Document Cache | ~10GB | - |
| **Gesamt** | ~20GB | ~20GB |

---

## Naechste Schritte

1. **Ollama auf Mac installieren** (5 min)
   ```bash
   brew install ollama && ollama pull mistral && ollama pull nomic-embed-text
   ```

2. **OllamaClient.swift erstellen** (30 min)

3. **Docker Compose auf Windows aufsetzen** (1-2 Stunden)

4. **MCP Server deployen** (1 Stunde)

5. **KnowledgeHubClient in SCRAINEE integrieren** (2-3 Stunden)

6. **Batch-Import existierender Dokumente** (je nach Datenmenge)

---

## Referenzen

- [Ollama Documentation](https://ollama.com)
- [Qdrant Documentation](https://qdrant.tech/documentation/)
- [FastMCP](https://github.com/jlowin/fastmcp)
- [Unstructured.io](https://unstructured.io)
- [Tailscale](https://tailscale.com)
