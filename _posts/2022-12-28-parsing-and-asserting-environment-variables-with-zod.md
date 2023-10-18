---
layout: post
title: >
  Parsing and asserting environment variables with Zod
---

### Schema

First, we need to define a schema; my project relies on three environment variables. Translating to the following code:

```typescript
import { z } from "zod";

const schema = z.object({
  PORT: z.coerce.number().positive().default(3000),
  JWT_SECRET: z.string().min(6).max(256),
  MONGO_DSN: z.string().url(),
});

export const { PORT, JWT_SECRET, MONGO_DSN } = schema.parse(process.env);
```

Where:

- PORT is absent during development mode and defaults to 3000.
- JWT_SECRET is equals to `secret`, which is greater or equal to 6 and less than 256.
- MONGO_DSN is `mongodb://docker:docker@mongo:27017/` which is a valid URL.

### Using

To use is pretty simple. Just import it:

```typescript
import { PORT, JWT_SECRET, MONGO_DSN } from "./environment";
```

### Learn more

Please refer to the official documentation [zod.dev](https://zod.dev/).
