import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  ListToolsRequestSchema,
  CallToolRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';
import { GoogleGenAI } from '@google/genai';

// Initialize Gemini AI
const ai = new GoogleGenAI({
  apiKey: process.env.GOOGLE_API_KEY
});

// Create MCP server
const server = new Server(
  {
    name: 'gemini-mcp-server',
    version: '1.0.0'
  },
  {
    capabilities: {
      tools: {}
    }
  }
);

// Define available tools
const TOOLS = [
  {
    name: 'gemini_chat',
    description: 'Chat with Gemini 2.5 Pro model',
    inputSchema: {
      type: 'object',
      properties: {
        message: {
          type: 'string',
          description: 'The message to send to Gemini'
        },
        model: {
          type: 'string',
          description: 'Gemini model to use',
          enum: ['gemini-2.5-pro', 'gemini-2.5-flash'],
          default: 'gemini-2.5-pro'
        }
      },
      required: ['message']
    }
  },
  {
    name: 'gemini_generate_content',
    description: 'Generate content with Gemini 2.5 Pro with custom parameters',
    inputSchema: {
      type: 'object',
      properties: {
        prompt: {
          type: 'string',
          description: 'The prompt to generate content from'
        },
        model: {
          type: 'string',
          description: 'Gemini model to use',
          enum: ['gemini-2.5-pro', 'gemini-2.5-flash'],
          default: 'gemini-2.5-pro'
        },
        temperature: {
          type: 'number',
          description: 'Temperature for generation (0.0-2.0)',
          minimum: 0.0,
          maximum: 2.0,
          default: 1.0
        },
        maxOutputTokens: {
          type: 'number',
          description: 'Maximum number of output tokens',
          minimum: 1,
          maximum: 8192,
          default: 2048
        }
      },
      required: ['prompt']
    }
  },
  {
    name: 'gemini_search',
    description: 'Search the web using Google Search grounding with Gemini',
    inputSchema: {
      type: 'object',
      properties: {
        query: {
          type: 'string',
          description: 'The search query or question to answer with real-time web information'
        },
        model: {
          type: 'string',
          description: 'Gemini model to use',
          enum: ['gemini-2.5-pro', 'gemini-2.5-flash'],
          default: 'gemini-2.5-flash'
        }
      },
      required: ['query']
    }
  },
  {
    name: 'gemini_search_with_context',
    description: 'Search the web with additional context using Google Search grounding',
    inputSchema: {
      type: 'object',
      properties: {
        query: {
          type: 'string',
          description: 'The search query or question'
        },
        context: {
          type: 'string',
          description: 'Additional context to help with the search'
        },
        model: {
          type: 'string',
          description: 'Gemini model to use',
          enum: ['gemini-2.5-pro', 'gemini-2.5-flash'],
          default: 'gemini-2.5-flash'
        },
        temperature: {
          type: 'number',
          description: 'Temperature for generation (0.0-2.0)',
          minimum: 0.0,
          maximum: 2.0,
          default: 0.3
        }
      },
      required: ['query']
    }
  }
];

// List tools handler
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: TOOLS
}));

// Call tool handler
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case 'gemini_chat': {
        const { message, model = 'gemini-2.5-pro' } = args;

        const response = await ai.models.generateContent({
          model,
          contents: message,
        });

        return {
          content: [{
            type: 'text',
            text: response.text || 'No response generated'
          }]
        };
      }

      case 'gemini_generate_content': {
        const {
          prompt,
          model = 'gemini-2.5-pro',
          temperature = 1.0,
          maxOutputTokens = 2048
        } = args;

        const response = await ai.models.generateContent({
          model,
          contents: prompt,
          config: {
            temperature,
            maxOutputTokens
          }
        });

        return {
          content: [{
            type: 'text',
            text: response.text || 'No response generated'
          }]
        };
      }

      case 'gemini_search': {
        const { query, model = 'gemini-2.5-flash' } = args;

        const groundingTool = {
          googleSearch: {},
        };

        const response = await ai.models.generateContent({
          model,
          contents: query,
          config: {
            tools: [groundingTool]
          }
        });

        return {
          content: [{
            type: 'text',
            text: response.text || 'No search results found'
          }]
        };
      }

      case 'gemini_search_with_context': {
        const {
          query,
          context = '',
          model = 'gemini-2.5-flash',
          temperature = 0.3
        } = args;

        const groundingTool = {
          googleSearch: {},
        };

        const contextualQuery = context
          ? `Context: ${context}\n\nQuery: ${query}`
          : query;

        const response = await ai.models.generateContent({
          model,
          contents: contextualQuery,
          config: {
            tools: [groundingTool],
            temperature
          }
        });

        return {
          content: [{
            type: 'text',
            text: response.text || 'No search results found'
          }]
        };
      }

      default:
        throw new Error(`Unknown tool: ${name}`);
    }
  } catch (error) {
    throw new Error(`Tool execution failed: ${error.message}`);
  }
});

// Error handling
process.on('uncaughtException', (error) => {
  console.error('Uncaught Exception:', error);
  process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
  process.exit(1);
});

// Start the server
const transport = new StdioServerTransport();
await server.connect(transport);

// Graceful shutdown
process.on('SIGINT', () => {
  process.exit(0);
});

process.on('SIGTERM', () => {
  process.exit(0);
});
