import Foundation

struct WorkflowTemplate: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String        // SF Symbol name
    let steps: [WorkflowStep]
}

// MARK: - Template Library

enum WorkflowTemplates {
    static let all: [WorkflowTemplate] = [ragQA, deepSummarizer, keywordExpander, multiHop, balancedAnalysis]

    /// Retrieve relevant chunks then answer the question directly.
    static let ragQA = WorkflowTemplate(
        id: "rag_qa",
        name: "RAG Q&A",
        description: "Retrieves the most relevant passages from your knowledge base and answers your question with citations.",
        icon: "magnifyingglass.circle",
        steps: [
            WorkflowStep(type: .begin, label: "Input", outputSlot: "input"),
            WorkflowStep(type: .retrieve, label: "Retrieve", querySlot: "input", topK: 6, outputSlot: "context"),
            WorkflowStep(
                type: .llm,
                label: "Answer",
                promptTemplate: """
                You are a helpful assistant. Use only the provided context to answer the question. \
                If the context does not contain enough information, say so clearly.

                Context:
                {context}

                Question: {input}
                """,
                outputSlot: "output"
            ),
            WorkflowStep(type: .answer, label: "Result", outputSlot: "output"),
        ]
    )

    /// Retrieve many chunks and produce a comprehensive summary.
    static let deepSummarizer = WorkflowTemplate(
        id: "deep_summarizer",
        name: "Deep Summarizer",
        description: "Fetches a broad sample of your documents and produces a structured summary.",
        icon: "doc.text.magnifyingglass",
        steps: [
            WorkflowStep(type: .begin, label: "Input", outputSlot: "input"),
            WorkflowStep(type: .retrieve, label: "Broad Retrieve", querySlot: "input", topK: 15, outputSlot: "context"),
            WorkflowStep(
                type: .llm,
                label: "Summarize",
                promptTemplate: """
                Produce a clear, structured summary of the following passages. \
                Use headings where appropriate. Focus on key facts, themes, and insights.

                Topic: {input}

                Source passages:
                {context}
                """,
                outputSlot: "output"
            ),
            WorkflowStep(type: .answer, label: "Summary", outputSlot: "output"),
        ]
    )

    /// Let the LLM expand the query into keywords first, then retrieve.
    static let keywordExpander = WorkflowTemplate(
        id: "keyword_expander",
        name: "Keyword Expander",
        description: "Expands your query into precise search terms first, retrieves more targeted results, then answers.",
        icon: "text.word.spacing",
        steps: [
            WorkflowStep(type: .begin, label: "Input", outputSlot: "input"),
            WorkflowStep(
                type: .llm,
                label: "Extract Keywords",
                promptTemplate: """
                Generate 5 precise search keywords or short phrases for the following question. \
                Return only the keywords, comma-separated, nothing else.

                Question: {input}
                """,
                outputSlot: "keywords"
            ),
            WorkflowStep(type: .retrieve, label: "Targeted Retrieve", querySlot: "keywords", topK: 8, outputSlot: "context"),
            WorkflowStep(
                type: .llm,
                label: "Answer",
                promptTemplate: """
                Use the context below to answer the original question thoroughly.

                Context:
                {context}

                Original question: {input}
                """,
                outputSlot: "output"
            ),
            WorkflowStep(type: .answer, label: "Result", outputSlot: "output"),
        ]
    )

    /// Two retrieval hops: first retrieve → identify gaps → retrieve again → synthesize.
    static let multiHop = WorkflowTemplate(
        id: "multi_hop",
        name: "Multi-Hop Researcher",
        description: "Performs two rounds of retrieval to fill knowledge gaps before synthesizing a complete answer.",
        icon: "arrow.triangle.branch",
        steps: [
            WorkflowStep(type: .begin, label: "Input", outputSlot: "input"),
            WorkflowStep(type: .retrieve, label: "First Retrieve", querySlot: "input", topK: 6, outputSlot: "context1"),
            WorkflowStep(
                type: .llm,
                label: "Identify Gaps",
                promptTemplate: """
                Given this initial research on "{input}":

                {context1}

                What are 3 specific follow-up search queries that would fill important gaps? \
                Return only the queries, one per line.
                """,
                outputSlot: "followup"
            ),
            WorkflowStep(type: .retrieve, label: "Second Retrieve", querySlot: "followup", topK: 6, outputSlot: "context2"),
            WorkflowStep(
                type: .llm,
                label: "Synthesize",
                promptTemplate: """
                Synthesize a comprehensive answer to: {input}

                Initial findings:
                {context1}

                Additional research:
                {context2}
                """,
                outputSlot: "output"
            ),
            WorkflowStep(type: .answer, label: "Result", outputSlot: "output"),
        ]
    )

    /// Retrieve and provide a balanced, multi-perspective analysis.
    static let balancedAnalysis = WorkflowTemplate(
        id: "balanced_analysis",
        name: "Balanced Analysis",
        description: "Retrieves relevant material and presents multiple perspectives or sides of a topic.",
        icon: "scale.3d",
        steps: [
            WorkflowStep(type: .begin, label: "Input", outputSlot: "input"),
            WorkflowStep(type: .retrieve, label: "Retrieve", querySlot: "input", topK: 10, outputSlot: "context"),
            WorkflowStep(
                type: .llm,
                label: "Analyze",
                promptTemplate: """
                Based on the source material below, provide a balanced analysis of: {input}

                Present multiple perspectives where they exist. Highlight areas of agreement and disagreement. \
                Conclude with a synthesis of the key takeaways.

                Source material:
                {context}
                """,
                outputSlot: "output"
            ),
            WorkflowStep(type: .answer, label: "Analysis", outputSlot: "output"),
        ]
    )

    static func template(id: String) -> WorkflowTemplate? {
        all.first { $0.id == id }
    }
}
