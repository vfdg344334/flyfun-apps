#!/usr/bin/env python3
"""
Unit tests for RAG system (rules_rag.py).
"""
import json
import os
import tempfile
from pathlib import Path
from unittest.mock import Mock, patch

import pytest

from shared.aviation_agent.rules_rag import (
    EmbeddingProvider,
    QueryReformulator,
    RulesRAG,
    build_vector_db,
)


@pytest.fixture
def sample_rules_json(tmp_path):
    """Create a sample rules.json file for testing."""
    rules_data = {
        "questions": [
            {
                "question_id": "test-q1",
                "question_text": "Is a flight plan required for VFR flights?",
                "category": "VFR",
                "tags": ["vfr", "flight_plan"],
                "answers_by_country": {
                    "FR": {
                        "answer_html": "No, not required for VFR in France.",
                        "links": ["https://example.com/fr"],
                        "last_reviewed": "2025-01-01"
                    },
                    "GB": {
                        "answer_html": "No, not required for VFR in UK.",
                        "links": ["https://example.com/gb"],
                        "last_reviewed": "2025-01-01"
                    }
                }
            },
            {
                "question_id": "test-q2",
                "question_text": "What are the customs clearance requirements?",
                "category": "Customs",
                "tags": ["customs", "international"],
                "answers_by_country": {
                    "FR": {
                        "answer_html": "Must clear at designated POE.",
                        "links": [],
                        "last_reviewed": "2025-01-01"
                    }
                }
            }
        ]
    }
    
    rules_file = tmp_path / "test_rules.json"
    rules_file.write_text(json.dumps(rules_data), encoding="utf-8")
    return rules_file


class TestEmbeddingProvider:
    """Tests for EmbeddingProvider class."""
    
    @patch.dict('os.environ', {'OPENAI_API_KEY': 'test-key'})
    def test_openai_model_initialization(self):
        """Test initialization with OpenAI model."""
        with patch('shared.aviation_agent.rules_rag.OpenAIEmbeddings') as mock_embeddings:
            provider = EmbeddingProvider("text-embedding-3-small")
            assert provider.model_name == "text-embedding-3-small"
            assert provider.provider == "openai"
            mock_embeddings.assert_called_once_with(model="text-embedding-3-small")
    
    @patch.dict('os.environ', {'OPENAI_API_KEY': 'test-key'})
    def test_embed_texts(self):
        """Test embedding generation for multiple texts."""
        with patch('shared.aviation_agent.rules_rag.OpenAIEmbeddings') as mock_embeddings_class:
            mock_embeddings = Mock()
            mock_embeddings.embed_documents.return_value = [[0.1] * 1536, [0.2] * 1536]
            mock_embeddings_class.return_value = mock_embeddings
            
            provider = EmbeddingProvider("text-embedding-3-small")
            texts = ["Hello world", "Aviation rules"]
            embeddings = provider.embed(texts)
            
            assert len(embeddings) == 2
            assert all(isinstance(e, list) for e in embeddings)
            assert all(len(e) == 1536 for e in embeddings)  # OpenAI small dimension
            mock_embeddings.embed_documents.assert_called_once_with(texts)
    
    @patch.dict('os.environ', {'OPENAI_API_KEY': 'test-key'})
    def test_embed_query(self):
        """Test single query embedding."""
        with patch('shared.aviation_agent.rules_rag.OpenAIEmbeddings') as mock_embeddings_class:
            mock_embeddings = Mock()
            mock_embeddings.embed_query.return_value = [0.1] * 1536
            mock_embeddings_class.return_value = mock_embeddings
            
            provider = EmbeddingProvider("text-embedding-3-small")
            embedding = provider.embed_query("Test query")
            
            assert isinstance(embedding, list)
            assert len(embedding) == 1536
            mock_embeddings.embed_query.assert_called_once_with("Test query")
    
    @patch.dict('os.environ', {'OPENAI_API_KEY': 'test-key'})
    def test_empty_texts(self):
        """Test handling of empty text list."""
        with patch('shared.aviation_agent.rules_rag.OpenAIEmbeddings'):
            provider = EmbeddingProvider("text-embedding-3-small")
            embeddings = provider.embed([])
            assert embeddings == []
    
    def test_invalid_model(self):
        """Test that invalid model names raise ValueError."""
        with pytest.raises(ValueError, match="Unsupported embedding model"):
            EmbeddingProvider("all-MiniLM-L6-v2")


class TestQueryReformulator:
    """Tests for QueryReformulator class."""
    
    def test_reformulation_with_mock_llm(self):
        """Test query reformulation with mocked LLM."""
        mock_llm = Mock()
        mock_response = Mock()
        mock_response.content = "What are the flight plan filing requirements?"
        mock_llm.invoke.return_value = mock_response
        
        reformulator = QueryReformulator(llm=mock_llm)
        result = reformulator.reformulate("Do I need to file a flight plan?")
        
        assert result == "What are the flight plan filing requirements?"
        mock_llm.invoke.assert_called_once()
    
    def test_reformulation_without_llm(self):
        """Test that original query is returned when no LLM available."""
        reformulator = QueryReformulator(llm=None)
        reformulator._initialized = True  # Skip lazy init
        
        original = "Do I need to file a flight plan?"
        result = reformulator.reformulate(original)
        assert result == original
    
    def test_reformulation_failure_fallback(self):
        """Test fallback to original query on reformulation failure."""
        mock_llm = Mock()
        mock_llm.invoke.side_effect = Exception("API error")
        
        reformulator = QueryReformulator(llm=mock_llm)
        original = "Test query"
        result = reformulator.reformulate(original)
        
        assert result == original


class TestBuildVectorDB:
    """Tests for build_vector_db function."""
    
    def test_build_from_sample_rules(self, sample_rules_json, tmp_path):
        """Test building vector DB from sample rules.json."""
        vector_db_path = tmp_path / "test_vector_db"
        
        doc_count = build_vector_db(
            rules_json_path=sample_rules_json,
            vector_db_path=vector_db_path,
            embedding_model="text-embedding-3-small",
            force_rebuild=True
        )
        
        # Should have 3 documents (2 countries for q1 + 1 country for q2)
        assert doc_count == 3
        assert vector_db_path.exists()
    
    def test_build_with_missing_file(self, tmp_path):
        """Test error handling when rules.json doesn't exist."""
        with pytest.raises(FileNotFoundError):
            build_vector_db(
                rules_json_path=tmp_path / "nonexistent.json",
                vector_db_path=tmp_path / "db",
                force_rebuild=True
            )
    
    def test_no_rebuild_when_exists(self, sample_rules_json, tmp_path):
        """Test that existing DB is not rebuilt without force_rebuild."""
        vector_db_path = tmp_path / "test_vector_db"
        
        # First build
        count1 = build_vector_db(
            rules_json_path=sample_rules_json,
            vector_db_path=vector_db_path,
            force_rebuild=True
        )
        
        # Second build without force_rebuild
        count2 = build_vector_db(
            rules_json_path=sample_rules_json,
            vector_db_path=vector_db_path,
            force_rebuild=False  # Should skip rebuild
        )
        
        assert count1 == count2


class TestRulesRAG:
    """Tests for RulesRAG class."""
    
    @pytest.fixture
    def rag_system(self, sample_rules_json, tmp_path):
        """Create a RAG system with test data."""
        vector_db_path = tmp_path / "test_vector_db"
        
        # Build vector DB
        build_vector_db(
            rules_json_path=sample_rules_json,
            vector_db_path=vector_db_path,
            force_rebuild=True
        )
        
        # Initialize RAG system (no reformulation for tests)
        return RulesRAG(
            vector_db_path=vector_db_path,
            enable_reformulation=False
        )
    
    def test_initialization(self, rag_system):
        """Test RAG system initialization."""
        assert rag_system.collection is not None
        assert rag_system.collection.count() == 3
    
    def test_retrieve_rules_basic(self, rag_system):
        """Test basic rule retrieval."""
        results = rag_system.retrieve_rules(
            query="Is a flight plan required?",
            countries=["FR"],
            top_k=3
        )
        
        assert len(results) > 0
        assert all(r['country_code'] == 'FR' for r in results)
        assert all('question_text' in r for r in results)
        assert all('similarity' in r for r in results)
    
    def test_retrieve_multi_country(self, rag_system):
        """Test retrieval with multiple countries."""
        results = rag_system.retrieve_rules(
            query="Flight plan requirements",
            countries=["FR", "GB"],
            top_k=2
        )
        
        assert len(results) > 0
        # Should have results from both countries
        countries = {r['country_code'] for r in results}
        assert len(countries) > 0  # At least one country
    
    def test_retrieve_no_country_filter(self, rag_system):
        """Test retrieval without country filter."""
        results = rag_system.retrieve_rules(
            query="Flight plan",
            countries=None,
            top_k=3
        )
        
        assert len(results) > 0
    
    def test_retrieve_with_threshold(self, rag_system):
        """Test similarity threshold filtering."""
        results_low = rag_system.retrieve_rules(
            query="unrelated gibberish xyz123",
            countries=["FR"],
            top_k=10,
            similarity_threshold=0.5  # High threshold
        )
        
        # Should have few or no results due to high threshold
        assert len(results_low) <= 1
    
    def test_result_structure(self, rag_system):
        """Test that results have expected structure."""
        results = rag_system.retrieve_rules(
            query="Flight plan",
            countries=["FR"],
            top_k=1
        )
        
        assert len(results) > 0
        result = results[0]
        
        # Check required fields
        assert 'id' in result
        assert 'question_id' in result
        assert 'question_text' in result
        assert 'similarity' in result
        assert 'country_code' in result
        assert 'category' in result
        assert 'answer_html' in result
        assert 'links' in result
        
        # Check types
        assert isinstance(result['similarity'], (int, float))
        assert isinstance(result['links'], list)
        assert 0 <= result['similarity'] <= 1


@pytest.mark.integration
class TestRulesRAGIntegration:
    """Integration tests requiring full rules.json."""
    
    def test_production_vector_db(self):
        """Test with production vector DB if available."""
        vector_db_path = Path("cache/rules_vector_db")
        
        if not vector_db_path.exists():
            pytest.skip("Production vector DB not built")
        
        rag = RulesRAG(vector_db_path, enable_reformulation=False)
        
        # Test a real query
        results = rag.retrieve_rules(
            query="Do I need to file a flight plan?",
            countries=["FR"],
            top_k=3
        )
        
        assert len(results) > 0
        assert all(r['country_code'] == 'FR' for r in results)
        
        # Check quality - top result should be about flight plans
        top_result = results[0]
        assert any(term in top_result['question_text'].lower() 
                  for term in ['flight plan', 'fpl'])


if __name__ == "__main__":
    pytest.main([__file__, "-v"])

