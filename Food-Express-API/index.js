const express = require("express");
const jwt = require("jsonwebtoken");
const bcrypt = require("bcryptjs");

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 7000;
const JWT_SECRET = process.env.JWT_SECRET || "dev_secret_key";

// In-memory data (for demo only)
const users = [];
const items = [];

/*
  USER SHAPE
  {
    id,
    username,
    password
  }

  ITEM SHAPE
  {
    id,
    name,
    price,
    ownerId
  }
*/

// Helper: generate token
function generateToken(user) {
  return jwt.sign(
    { id: user.id, username: user.username },
    JWT_SECRET,
    { expiresIn: "1h" }
  );
}

// Middleware: auth
function authMiddleware(req, res, next) {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return res.status(401).json({ message: "Access denied. No token provided." });
  }

  const token = authHeader.split(" ")[1];

  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    req.user = decoded;
    next();
  } catch (error) {
    return res.status(401).json({ message: "Invalid or expired token." });
  }
}

// Home
app.get("/", (req, res) => {
  res.send("FoodExpress API is running 🚀");
});

// Health
app.get("/health", (req, res) => {
  res.json({ status: "healthy", service: "FoodExpress API" });
});

// Register
app.post("/auth/register", async (req, res) => {
  try {
    const { username, password } = req.body;

    if (!username || !password) {
      return res.status(400).json({ message: "Username and password are required." });
    }

    const existingUser = users.find((u) => u.username === username);
    if (existingUser) {
      return res.status(409).json({ message: "User already exists." });
    }

    const hashedPassword = await bcrypt.hash(password, 10);

    const newUser = {
      id: users.length + 1,
      username,
      password: hashedPassword,
    };

    users.push(newUser);

    res.status(201).json({
      message: "User registered successfully",
      user: {
        id: newUser.id,
        username: newUser.username,
      },
    });
  } catch (error) {
    res.status(500).json({ message: "Server error", error: error.message });
  }
});

// Login
app.post("/auth/login", async (req, res) => {
  try {
    const { username, password } = req.body;

    if (!username || !password) {
      return res.status(400).json({ message: "Username and password are required." });
    }

    const user = users.find((u) => u.username === username);
    if (!user) {
      return res.status(401).json({ message: "Invalid credentials." });
    }

    const isMatch = await bcrypt.compare(password, user.password);
    if (!isMatch) {
      return res.status(401).json({ message: "Invalid credentials." });
    }

    const token = generateToken(user);

    res.json({
      message: "Login successful",
      token,
      user: {
        id: user.id,
        username: user.username,
      },
    });
  } catch (error) {
    res.status(500).json({ message: "Server error", error: error.message });
  }
});

// Protected profile route
app.get("/auth/me", authMiddleware, (req, res) => {
  res.json({
    message: "Authorized user",
    user: req.user,
  });
});

// Get all items for logged-in user
app.get("/items", authMiddleware, (req, res) => {
  const userItems = items.filter((item) => item.ownerId === req.user.id);
  res.json(userItems);
});

// Get one item
app.get("/items/:id", authMiddleware, (req, res) => {
  const itemId = Number(req.params.id);

  const item = items.find(
    (i) => i.id === itemId && i.ownerId === req.user.id
  );

  if (!item) {
    return res.status(404).json({ message: "Item not found." });
  }

  res.json(item);
});

// Add item
app.post("/items", authMiddleware, (req, res) => {
  const { name, price } = req.body;

  if (!name || price === undefined) {
    return res.status(400).json({ message: "Name and price are required." });
  }

  const newItem = {
    id: items.length + 1,
    name,
    price,
    ownerId: req.user.id,
  };

  items.push(newItem);

  res.status(201).json({
    message: "Item added successfully",
    item: newItem,
  });
});

// Update item
app.put("/items/:id", authMiddleware, (req, res) => {
  const itemId = Number(req.params.id);
  const { name, price } = req.body;

  const item = items.find(
    (i) => i.id === itemId && i.ownerId === req.user.id
  );

  if (!item) {
    return res.status(404).json({ message: "Item not found." });
  }

  if (name !== undefined) item.name = name;
  if (price !== undefined) item.price = price;

  res.json({
    message: "Item updated successfully",
    item,
  });
});

// Delete item
app.delete("/items/:id", authMiddleware, (req, res) => {
  const itemId = Number(req.params.id);

  const itemIndex = items.findIndex(
    (i) => i.id === itemId && i.ownerId === req.user.id
  );

  if (itemIndex === -1) {
    return res.status(404).json({ message: "Item not found." });
  }

  const deletedItem = items.splice(itemIndex, 1);

  res.json({
    message: "Item deleted successfully",
    item: deletedItem[0],
  });
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`Server start running on port ${PORT}`);
});