// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, use_key_in_widget_constructors, library_private_types_in_public_api, unnecessary_string_interpolations, unreachable_switch_default, deprecated_member_use, unnecessary_to_list_in_spreads, depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'dart:collection';
import 'dart:math';
import 'package:table_calendar/table_calendar.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// ===========================================================================
// 1. ТОЧКА ВХОДА (MAIN)
// ===========================================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru_RU', null);
  
  runApp(
    ChangeNotifierProvider(
      create: (context) => PastryProvider(),
      child: PastryProApp(),
    ),
  );
}


// === ЭКРАН ЗАГРУЗКИ ===
class AppLoader extends StatefulWidget {
  @override
  _AppLoaderState createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader> {
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final provider = Provider.of<PastryProvider>(context, listen: false);
    await provider.loadData();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context);
    
    if (!provider.isLoaded) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.pink),
              SizedBox(height: 16),
              Text('Загрузка данных...', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }
    
    return MainScreen();
  }
}

// ===========================================================================
// 2. МОДЕЛИ ДАННЫХ (с сериализацией)
// ===========================================================================
enum OrderStatus { inProgress, ready, completed }
enum IngredientType { ingredient, decoration, packaging }

class Ingredient {
  String id;
  String name;
  double price;
  double packageSize;
  IngredientType type;

  Ingredient({
    required this.id,
    required this.name,
    required this.price,
    required this.packageSize,
    this.type = IngredientType.ingredient,
  });
  
  double get pricePerUnit => (packageSize > 0) ? price / packageSize : 0;

  // === СЕРИАЛИЗАЦИЯ ===
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'price': price,
    'packageSize': packageSize,
    'type': type.index,
  };

  factory Ingredient.fromJson(Map<String, dynamic> json) => Ingredient(
    id: json['id'],
    name: json['name'],
    price: (json['price'] as num).toDouble(),
    packageSize: (json['packageSize'] as num).toDouble(),
    type: IngredientType.values[json['type']],
  );
}

class RecipeComponent {
  String ingredientId;
  double quantity;

  RecipeComponent({required this.ingredientId, required this.quantity});

  Map<String, dynamic> toJson() => {
    'ingredientId': ingredientId,
    'quantity': quantity,
  };

  factory RecipeComponent.fromJson(Map<String, dynamic> json) => RecipeComponent(
    ingredientId: json['ingredientId'],
    quantity: (json['quantity'] as num).toDouble(),
  );
}

class InventoryItem {
  String id;
  String productId;
  String productName;
  int quantity;
  int availableQuantity;
  DateTime productionDate;
  double unitCostAtTimeOfProduction;

  InventoryItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.productionDate,
    required this.unitCostAtTimeOfProduction,
    int? availableQuantity,
  }) : availableQuantity = availableQuantity ?? quantity;

  Map<String, dynamic> toJson() => {
    'id': id,
    'productId': productId,
    'productName': productName,
    'quantity': quantity,
    'availableQuantity': availableQuantity,
    'productionDate': productionDate.toIso8601String(),
    'unitCostAtTimeOfProduction': unitCostAtTimeOfProduction,
  };

  factory InventoryItem.fromJson(Map<String, dynamic> json) => InventoryItem(
    id: json['id'],
    productId: json['productId'],
    productName: json['productName'],
    quantity: json['quantity'],
    availableQuantity: json['availableQuantity'],
    productionDate: DateTime.parse(json['productionDate']),
    unitCostAtTimeOfProduction: (json['unitCostAtTimeOfProduction'] as num).toDouble(),
  );
}

class Product {
  String id;
  String name;
  List<RecipeComponent> ingredients;
  int producedQuantity;
  bool isWeightBased;

  Product({
    required this.id,
    required this.name,
    this.ingredients = const [],
    this.producedQuantity = 1,
    this.isWeightBased = false,
  });

  double getBaseWeight() {
    double total = 0;
    for (var component in ingredients) {
      total += component.quantity;
    }
    return total;
  }

  double getCost(List<Ingredient> allIngredients) {
    double totalCost = 0.0;
    for (var component in ingredients) {
      try {
        final ingredient = allIngredients
            .firstWhere((ing) => ing.id == component.ingredientId);
        totalCost += ingredient.pricePerUnit * component.quantity;
      } catch (e) {}
    }
    return totalCost;
  }

  double getUnitCost(List<Ingredient> allIngredients) {
    if (isWeightBased || producedQuantity <= 0) return 0.0;
    return getCost(allIngredients) / producedQuantity;
  }

  double getCostPerGram(List<Ingredient> allIngredients) {
    if (!isWeightBased) return 0.0;
    final baseWeight = getBaseWeight();
    if (baseWeight <= 0) return 0.0;
    return getCost(allIngredients) / baseWeight;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'ingredients': ingredients.map((e) => e.toJson()).toList(),
    'producedQuantity': producedQuantity,
    'isWeightBased': isWeightBased,
  };

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json['id'],
    name: json['name'],
    ingredients: (json['ingredients'] as List)
        .map((e) => RecipeComponent.fromJson(e))
        .toList(),
    producedQuantity: json['producedQuantity'],
    isWeightBased: json['isWeightBased'] ?? false,
  );
}

class OrderDecorationPackagingItem {
  String id;
  String? itemId;
  double quantity;
  String itemName;
  double itemPriceAtTime;

  OrderDecorationPackagingItem({
    required this.id,
    this.itemId,
    this.quantity = 0,
    required this.itemName,
    required this.itemPriceAtTime,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'itemId': itemId,
    'quantity': quantity,
    'itemName': itemName,
    'itemPriceAtTime': itemPriceAtTime,
  };

  factory OrderDecorationPackagingItem.fromJson(Map<String, dynamic> json) =>
      OrderDecorationPackagingItem(
        id: json['id'],
        itemId: json['itemId'],
        quantity: (json['quantity'] as num).toDouble(),
        itemName: json['itemName'],
        itemPriceAtTime: (json['itemPriceAtTime'] as num).toDouble(),
      );
}

class OrderItem {
  String id;
  String productId;
  String productName;
  String? inventoryItemId;
  double unitCostFromInventory;
  int quantity;
  double sellingPrice;
  List<OrderDecorationPackagingItem> decorations;
  List<OrderDecorationPackagingItem> packaging;
  bool isWeightBased;
  double? weight;
  double costPerGram;
  double pricePerGram;

  OrderItem({
    required this.id,
    required this.productId,
    required this.productName,
    this.inventoryItemId,
    this.unitCostFromInventory = 0,
    this.quantity = 1,
    this.sellingPrice = 0,
    List<OrderDecorationPackagingItem>? decorations,
    List<OrderDecorationPackagingItem>? packaging,
    this.isWeightBased = false,
    this.weight,
    this.costPerGram = 0,
    this.pricePerGram = 0,
  })  : decorations = decorations ?? [],
        packaging = packaging ?? [];

  double getTotalCost() {
    double baseCost;
    if (isWeightBased) {
      baseCost = costPerGram * (weight ?? 0);
    } else {
      baseCost = unitCostFromInventory * quantity;
    }
    double decoCost = 0;
    double packCost = 0;
    for (var d in decorations) {
      decoCost += d.itemPriceAtTime * d.quantity;
    }
    for (var p in packaging) {
      packCost += p.itemPriceAtTime * p.quantity;
    }
    if (!isWeightBased) {
      decoCost *= quantity;
      packCost *= quantity;
    }
    return baseCost + decoCost + packCost;
  }

  double getTotalPrice() {
    if (isWeightBased) {
      return pricePerGram * (weight ?? 0);
    }
    return sellingPrice * quantity;
  }

  double getProfit() => getTotalPrice() - getTotalCost();

  double getDecorationCost() {
    double total = 0;
    for (var d in decorations) {
      total += d.itemPriceAtTime * d.quantity;
    }
    if (!isWeightBased) total *= quantity;
    return total;
  }

  double getPackagingCost() {
    double total = 0;
    for (var p in packaging) {
      total += p.itemPriceAtTime * p.quantity;
    }
    if (!isWeightBased) total *= quantity;
    return total;
  }

  String get tabName {
    if (productName.isEmpty) return 'Новое изделие';
    if (isWeightBased && weight != null && weight! > 0) {
      return '$productName (${weight!.toStringAsFixed(0)}г)';
    }
    return productName;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'productId': productId,
    'productName': productName,
    'inventoryItemId': inventoryItemId,
    'unitCostFromInventory': unitCostFromInventory,
    'quantity': quantity,
    'sellingPrice': sellingPrice,
    'decorations': decorations.map((e) => e.toJson()).toList(),
    'packaging': packaging.map((e) => e.toJson()).toList(),
    'isWeightBased': isWeightBased,
    'weight': weight,
    'costPerGram': costPerGram,
    'pricePerGram': pricePerGram,
  };

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
    id: json['id'],
    productId: json['productId'],
    productName: json['productName'],
    inventoryItemId: json['inventoryItemId'],
    unitCostFromInventory: (json['unitCostFromInventory'] as num).toDouble(),
    quantity: json['quantity'],
    sellingPrice: (json['sellingPrice'] as num).toDouble(),
    decorations: (json['decorations'] as List)
        .map((e) => OrderDecorationPackagingItem.fromJson(e))
        .toList(),
    packaging: (json['packaging'] as List)
        .map((e) => OrderDecorationPackagingItem.fromJson(e))
        .toList(),
    isWeightBased: json['isWeightBased'] ?? false,
    weight: json['weight'] != null ? (json['weight'] as num).toDouble() : null,
    costPerGram: (json['costPerGram'] as num?)?.toDouble() ?? 0,
    pricePerGram: (json['pricePerGram'] as num?)?.toDouble() ?? 0,
  );
}

class Order {
  String id;
  String customerName;
  String? customerPhone;
  DateTime orderDate;
  DateTime deliveryDate;
  OrderStatus status;
  List<OrderItem> items;

  Order({
    required this.id,
    required this.customerName,
    this.customerPhone,
    required this.orderDate,
    DateTime? deliveryDate,
    this.status = OrderStatus.inProgress,
    List<OrderItem>? items,
  }) : deliveryDate = deliveryDate ?? orderDate,
       items = items ?? [];

  double getTotalCost() =>
      items.fold(0.0, (sum, item) => sum + item.getTotalCost());

  double getTotalPrice() =>
      items.fold(0.0, (sum, item) => sum + item.getTotalPrice());

  double getProfit() => getTotalPrice() - getTotalCost();

  double getTotalDecorationCost() =>
      items.fold(0.0, (sum, item) => sum + item.getDecorationCost());

  double getTotalPackagingCost() =>
      items.fold(0.0, (sum, item) => sum + item.getPackagingCost());

  String get shortDescription {
    if (items.isEmpty) return 'Пустой заказ';
    if (items.length == 1) return items.first.productName;
    return '${items.first.productName} +${items.length - 1}';
  }

  String get itemsList =>
      items.map((i) => '${i.productName} x${i.quantity}').join(', ');

  Map<String, dynamic> toJson() => {
    'id': id,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'orderDate': orderDate.toIso8601String(),
    'deliveryDate': deliveryDate.toIso8601String(),
    'status': status.index,
    'items': items.map((e) => e.toJson()).toList(),
  };

  factory Order.fromJson(Map<String, dynamic> json) => Order(
    id: json['id'],
    customerName: json['customerName'],
    customerPhone: json['customerPhone'],
    orderDate: DateTime.parse(json['orderDate']),
    deliveryDate: DateTime.parse(json['deliveryDate']),
    status: OrderStatus.values[json['status']],
    items: (json['items'] as List)
        .map((e) => OrderItem.fromJson(e))
        .toList(),
  );
}

// ===========================================================================
// 3. УПРАВЛЕНИЕ СОСТОЯНИЕМ (PROVIDER) С СОХРАНЕНИЕМ
// ===========================================================================
class PastryProvider with ChangeNotifier {
  List<Ingredient> _ingredients = [];
  List<Product> _products = [];
  List<Order> _orders = [];
  List<InventoryItem> _inventory = [];
  
  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  UnmodifiableListView<Ingredient> get ingredients =>
      UnmodifiableListView(_ingredients);
  UnmodifiableListView<Product> get products => UnmodifiableListView(_products);
  UnmodifiableListView<Order> get orders => UnmodifiableListView(_orders);
  UnmodifiableListView<InventoryItem> get inventory =>
      UnmodifiableListView(_inventory);

  // === ИНИЦИАЛИЗАЦИЯ: ЗАГРУЗКА ДАННЫХ ===
  Future<void> loadData() async {
    if (_isLoaded) return;
    
    final prefs = await SharedPreferences.getInstance();
    
    // Загрузка ингредиентов
    final ingredientsJson = prefs.getString('ingredients');
    if (ingredientsJson != null) {
      final List<dynamic> decoded = jsonDecode(ingredientsJson);
      _ingredients = decoded.map((e) => Ingredient.fromJson(e)).toList();
    } else {
      // Начальные данные при первом запуске
      _ingredients = [
        Ingredient(
            id: 'ing1',
            name: 'Мука пшеничная',
            price: 60,
            packageSize: 1000,
            type: IngredientType.ingredient),
        Ingredient(
            id: 'ing2',
            name: 'Сахар',
            price: 80,
            packageSize: 1000,
            type: IngredientType.ingredient),
        Ingredient(
            id: 'ing3',
            name: 'Сливочное масло',
            price: 150,
            packageSize: 180,
            type: IngredientType.ingredient),
        Ingredient(
            id: 'dec1',
            name: 'Свежие ягоды',
            price: 250,
            packageSize: 100,
            type: IngredientType.decoration),
        Ingredient(
            id: 'pack1',
            name: 'Коробка для торта',
            price: 100,
            packageSize: 1,
            type: IngredientType.packaging),
      ];
    }
    
    // Загрузка изделий
    final productsJson = prefs.getString('products');
    if (productsJson != null) {
      final List<dynamic> decoded = jsonDecode(productsJson);
      _products = decoded.map((e) => Product.fromJson(e)).toList();
    } else {
      _products = [
        Product(
            id: 'prod1',
            name: 'Торт "Медовик"',
            producedQuantity: 1,
            ingredients: [
              RecipeComponent(ingredientId: 'ing1', quantity: 300),
              RecipeComponent(ingredientId: 'ing2', quantity: 200),
              RecipeComponent(ingredientId: 'ing3', quantity: 180)
            ])
      ];
    }
    
    // Загрузка заказов
    final ordersJson = prefs.getString('orders');
    if (ordersJson != null) {
      final List<dynamic> decoded = jsonDecode(ordersJson);
      _orders = decoded.map((e) => Order.fromJson(e)).toList();
    }
    
    // Загрузка запасов
    final inventoryJson = prefs.getString('inventory');
    if (inventoryJson != null) {
      final List<dynamic> decoded = jsonDecode(inventoryJson);
      _inventory = decoded.map((e) => InventoryItem.fromJson(e)).toList();
    }
    
    _isLoaded = true;
    notifyListeners();
  }

  // === СОХРАНЕНИЕ ДАННЫХ ===
  Future<void> _saveIngredients() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(_ingredients.map((e) => e.toJson()).toList());
    await prefs.setString('ingredients', jsonString);
  }

  Future<void> _saveProducts() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(_products.map((e) => e.toJson()).toList());
    await prefs.setString('products', jsonString);
  }

  Future<void> _saveOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(_orders.map((e) => e.toJson()).toList());
    await prefs.setString('orders', jsonString);
  }

  Future<void> _saveInventory() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(_inventory.map((e) => e.toJson()).toList());
    await prefs.setString('inventory', jsonString);
  }

  // === ОСТАЛЬНЫЕ МЕТОДЫ (обновлённые) ===
  
  List<Ingredient> getIngredientsByType(IngredientType type) =>
      _ingredients.where((ing) => ing.type == type).toList();

  String _generateId() =>
      DateTime.now().millisecondsSinceEpoch.toString() +
      Random().nextInt(999).toString();

  void addIngredient(Ingredient ingredient) {
    ingredient.id = _generateId();
    _ingredients.add(ingredient);
    _saveIngredients(); // ← сохраняем
    notifyListeners();
  }

  void updateIngredient(Ingredient updatedIngredient) {
    final index = _ingredients.indexWhere((i) => i.id == updatedIngredient.id);
    if (index != -1) {
      _ingredients[index] = updatedIngredient;
      _saveIngredients(); // ← сохраняем
      notifyListeners();
    }
  }

  void deleteIngredient(String id) {
    _ingredients.removeWhere((ingredient) => ingredient.id == id);
    _saveIngredients(); // ← сохраняем
    notifyListeners();
  }

  void addProduct(Product product) {
    product.id = _generateId();
    _products.add(product);
    _saveProducts(); // ← сохраняем
    notifyListeners();
  }

  void updateProduct(Product updatedProduct) {
    final index = _products.indexWhere((p) => p.id == updatedProduct.id);
    if (index != -1) {
      _products[index] = updatedProduct;
      _saveProducts(); // ← сохраняем
      notifyListeners();
    }
  }

  void deleteProduct(String id) {
    _products.removeWhere((product) => product.id == id);
    _saveProducts(); // ← сохраняем
    notifyListeners();
  }

  void addInventoryItem(InventoryItem item) {
    item.id = _generateId();
    _inventory.add(item);
    _saveInventory(); // ← сохраняем
    notifyListeners();
  }

  void updateInventoryItem(InventoryItem updatedItem) {
    final index = _inventory.indexWhere((i) => i.id == updatedItem.id);
    if (index != -1) {
      _inventory[index] = updatedItem;
      _saveInventory(); // ← сохраняем
      notifyListeners();
    }
  }

  void deleteInventoryItem(String id) {
    _inventory.removeWhere((item) => item.id == id);
    _saveInventory(); // ← сохраняем
    notifyListeners();
  }

  void addProductToInventory(
      String productId, int quantity, DateTime productionDate) {
    final product = _products.firstWhere((p) => p.id == productId,
        orElse: () => throw Exception('Product not found'));
    final unitCost = product.getUnitCost(_ingredients);

    if (unitCost <= 0 || quantity <= 0) {
      throw Exception('Неверные данные изделия или количество');
    }

    final existingIndex = _inventory.indexWhere((item) =>
        item.productId == productId &&
        isSameDay(item.productionDate, productionDate));

    if (existingIndex != -1) {
      _inventory[existingIndex].quantity += quantity;
      _inventory[existingIndex].availableQuantity += quantity;
    } else {
      final inventoryItem = InventoryItem(
        id: _generateId(),
        productId: product.id,
        productName: product.name,
        quantity: quantity,
        productionDate: productionDate,
        unitCostAtTimeOfProduction: unitCost,
        availableQuantity: quantity,
      );
      _inventory.add(inventoryItem);
    }
    _saveInventory(); // ← сохраняем
    notifyListeners();
  }

  List<InventoryItem> getAvailableInventoryForProduct(String productId) =>
      _inventory
          .where((item) =>
              item.productId == productId && item.availableQuantity > 0)
          .toList();

  void addOrder(Order order) {
    order.id = _generateId();
    _orders.add(order);

    for (var item in order.items) {
      if (item.inventoryItemId != null) {
        final inventoryIndex =
            _inventory.indexWhere((inv) => inv.id == item.inventoryItemId);
        if (inventoryIndex != -1) {
          _inventory[inventoryIndex].availableQuantity -= item.quantity;
        }
      }
    }
    _saveOrders(); // ← сохраняем
    _saveInventory(); // ← сохраняем запасы тоже
    notifyListeners();
  }

  void updateOrder(Order updatedOrder) {
    final index = _orders.indexWhere((o) => o.id == updatedOrder.id);
    if (index != -1) {
      final oldOrder = _orders[index];

      for (var item in oldOrder.items) {
        if (item.inventoryItemId != null) {
          final invIndex =
              _inventory.indexWhere((inv) => inv.id == item.inventoryItemId);
          if (invIndex != -1) {
            _inventory[invIndex].availableQuantity += item.quantity;
          }
        }
      }

      _orders[index] = updatedOrder;

      for (var item in updatedOrder.items) {
        if (item.inventoryItemId != null) {
          final invIndex =
              _inventory.indexWhere((inv) => inv.id == item.inventoryItemId);
          if (invIndex != -1) {
            _inventory[invIndex].availableQuantity -= item.quantity;
          }
        }
      }

      _saveOrders(); // ← сохраняем
      _saveInventory(); // ← сохраняем запасы тоже
      notifyListeners();
    }
  }

  void deleteOrder(String id) {
    final orderIndex = _orders.indexWhere((order) => order.id == id);
    if (orderIndex != -1) {
      final orderToDelete = _orders[orderIndex];

      for (var item in orderToDelete.items) {
        if (item.inventoryItemId != null) {
          final invIndex =
              _inventory.indexWhere((inv) => inv.id == item.inventoryItemId);
          if (invIndex != -1) {
            _inventory[invIndex].availableQuantity += item.quantity;
          }
        }
      }

      _orders.removeAt(orderIndex);
      _saveOrders(); // ← сохраняем
      _saveInventory(); // ← сохраняем запасы тоже
      notifyListeners();
    }
  }

  void updateOrderStatus(String orderId, OrderStatus newStatus) {
    final orderIndex = _orders.indexWhere((o) => o.id == orderId);
    if (orderIndex != -1) {
      _orders[orderIndex].status = newStatus;
      _saveOrders(); // ← сохраняем
      notifyListeners();
    }
  }

  Product getProductById(String id) => _products.firstWhere((p) => p.id == id,
      orElse: () =>
          Product(id: 'not_found', name: 'Изделие удалено', producedQuantity: 0));

  Ingredient getIngredientById(String id) => _ingredients.firstWhere(
      (i) => i.id == id,
      orElse: () => Ingredient(
          id: 'not_found',
          name: 'Ингредиент удален',
          price: 0,
          packageSize: 0,
          type: IngredientType.ingredient));

  Map<String, double> getStatistics() {
    final completedOrders =
        _orders.where((o) => o.status == OrderStatus.completed);
    double totalRevenue = 0, totalCost = 0;
    for (var order in completedOrders) {
      totalRevenue += order.getTotalPrice();
      totalCost += order.getTotalCost();
    }
    return {
      'revenue': totalRevenue,
      'cost': totalCost,
      'profit': totalRevenue - totalCost,
      'orderCount': completedOrders.length.toDouble()
    };
  }

  Map<String, double> getStatisticsForPeriod(
      DateTime startDate, DateTime endDate) {
    final completedOrders = _orders
        .where((o) => o.status == OrderStatus.completed)
        .where((o) =>
            (o.orderDate.isAfter(startDate) ||
                isSameDay(o.orderDate, startDate)) &&
            (o.orderDate.isBefore(endDate) || isSameDay(o.orderDate, endDate)))
        .toList();
    double totalRevenue = 0, totalCost = 0;
    Set<String> uniqueCustomers = {};
    for (var order in completedOrders) {
      totalRevenue += order.getTotalPrice();
      totalCost += order.getTotalCost();
      uniqueCustomers.add(order.customerName);
    }
    return {
      'revenue': totalRevenue,
      'cost': totalCost,
      'profit': totalRevenue - totalCost,
      'orderCount': completedOrders.length.toDouble(),
      'customerCount': uniqueCustomers.length.toDouble(),
    };
  }
}

// ===========================================================================
// 4. ГЛАВНОЕ ПРИЛОЖЕНИЕ И НАВИГАЦИЯ
// ===========================================================================
class PastryProApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Кондитер Про',
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: [
        const Locale('ru', 'RU'),
      ],
      theme: ThemeData(
          primarySwatch: Colors.pink,
          visualDensity: VisualDensity.adaptivePlatformDensity,
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink)),
      home: AppLoader(), // ← Новый загрузчик
      debugShowCheckedModeBanner: false,
    );
  }
}
class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  DateTime _selectedDayForNewOrder = DateTime.now();
  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

  void _updateSelectedDay(DateTime? day) {
    if (day != null) {
      setState(() => _selectedDayForNewOrder = day);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      OrdersScreen(onDaySelected: _updateSelectedDay),
      ProductsScreen(),
      IngredientsMainScreen(),
      InventoryScreen(),
      StatisticsScreen(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('Кондитер Про',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              shadows: [
                Shadow(
                  blurRadius: 4.0,
                  color: Colors.black26,
                  offset: Offset(2.0, 2.0),
                ),
              ],
            )),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        elevation: 8,
        shadowColor: Colors.black45,
      ),
      body: screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today), label: 'Заказы'),
          BottomNavigationBarItem(icon: Icon(Icons.cake), label: 'Изделия'),
          BottomNavigationBarItem(
              icon: Icon(Icons.list_alt), label: 'Справочник'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory), label: 'Запасы'),
          BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart), label: 'Статистика'),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
      floatingActionButton: _selectedIndex < 4
          ? FloatingActionButton(
              child: Icon(Icons.add),
              onPressed: () {
                if (_selectedIndex == 0) {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => OrderEditScreen(
                              selectedDate: _selectedDayForNewOrder)));
                } else if (_selectedIndex == 1) {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (context) => ProductEditScreen()));
                } else if (_selectedIndex == 2) {
                  _showIngredientTypeDialog(context);
                } else if (_selectedIndex == 3) {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (context) => AddToInventoryScreen()));
                }
              },
            )
          : null,
    );
  }

  void _showIngredientTypeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Выберите тип'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text('Ингредиенты'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              IngredientEditScreen(type: IngredientType.ingredient)));
                },
              ),
              ListTile(
                title: Text('Украшения'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              IngredientEditScreen(type: IngredientType.decoration)));
                },
              ),
              ListTile(
                title: Text('Упаковка'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              IngredientEditScreen(type: IngredientType.packaging)));
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// --- ЭКРАН ДОБАВЛЕНИЯ В ЗАПАСЫ ---
class AddToInventoryScreen extends StatefulWidget {
  @override
  _AddToInventoryScreenState createState() => _AddToInventoryScreenState();
}

class _AddToInventoryScreenState extends State<AddToInventoryScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedProductId;
  late TextEditingController _quantityController;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(text: '1');
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
      locale: const Locale('ru', 'RU'),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context, listen: false);
    return Scaffold(
      appBar: AppBar(title: Text('Добавить в запасы')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Выберите изделие:',
                  style: Theme.of(context).textTheme.titleMedium),
              SizedBox(height: 8),
              DropdownButtonFormField<String>(
                isExpanded: true,
                decoration: InputDecoration(
                    border: OutlineInputBorder(), labelText: 'Изделие'),
                value: _selectedProductId,
                items: provider.products
                    .map((product) => DropdownMenuItem(
                        value: product.id, child: Text(product.name)))
                    .toList(),
                onChanged: (value) => setState(() => _selectedProductId = value),
                validator: (value) => value == null ? 'Выберите изделие' : null,
              ),
              SizedBox(height: 16),
              Text('Дата изготовления:',
                  style: Theme.of(context).textTheme.titleMedium),
              SizedBox(height: 8),
              InkWell(
                onTap: () => _pickDate(context),
                child: InputDecorator(
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(DateFormat.yMd('ru_RU').format(_selectedDate),
                      style: TextStyle(fontSize: 16)),
                ),
              ),
              SizedBox(height: 16),
              Text('Введите количество:',
                  style: Theme.of(context).textTheme.titleMedium),
              SizedBox(height: 8),
              TextFormField(
                controller: _quantityController,
                decoration: InputDecoration(
                    border: OutlineInputBorder(), labelText: 'Количество'),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Введите количество';
                  final quantity = int.tryParse(value);
                  if (quantity == null || quantity <= 0) {
                    return 'Количество должно быть больше 0';
                  }
                  return null;
                },
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate() &&
                      _selectedProductId != null) {
                    try {
                      final quantity = int.parse(_quantityController.text);
                      provider.addProductToInventory(
                          _selectedProductId!, quantity, _selectedDate);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Изделие добавлено в запасы')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Ошибка: ${e.toString()}')),
                      );
                    }
                  }
                },
                child: Text('Добавить'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- ЭКРАН ЗАКАЗОВ ---
// --- ЭКРАН ЗАКАЗОВ С КАЛЕНДАРЁМ ---
class OrdersScreen extends StatefulWidget {
  final Function(DateTime?) onDaySelected;
  const OrdersScreen({required this.onDaySelected});

  @override
  _OrdersScreenState createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.week;
  OrderStatus? _selectedStatusFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onDaySelected(_selectedDay);
      }
    });
  }

  // Получаем заказы для конкретного дня (по дате выдачи)
  List<Order> _getOrdersForDay(DateTime day, List<Order> allOrders) {
    return allOrders.where((order) => isSameDay(order.deliveryDate, day)).toList();
  }

  // Получаем статус дня для отображения маркеров
  // Возвращает: 'hasInProgress', 'hasReady', 'allCompleted', 'empty'
  Map<String, int> _getDayStatus(DateTime day, List<Order> allOrders) {
    final ordersForDay = _getOrdersForDay(day, allOrders);
    
    int inProgressCount = 0;
    int readyCount = 0;
    int completedCount = 0;
    
    for (var order in ordersForDay) {
      switch (order.status) {
        case OrderStatus.inProgress:
          inProgressCount++;
          break;
        case OrderStatus.ready:
          readyCount++;
          break;
        case OrderStatus.completed:
          completedCount++;
          break;
      }
    }
    
    return {
      'inProgress': inProgressCount,
      'ready': readyCount,
      'completed': completedCount,
      'total': ordersForDay.length,
    };
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context);
    final List<Order> allOrders = List.from(provider.orders);
    
    // Фильтруем заказы для выбранного дня
    List<Order> filteredOrders = _getOrdersForDay(_selectedDay, allOrders);

    // Дополнительный фильтр по статусу
    if (_selectedStatusFilter != null) {
      filteredOrders = filteredOrders
          .where((order) => order.status == _selectedStatusFilter)
          .toList();
    }

    // Сортировка по дате создания (новые сверху)
    filteredOrders.sort((a, b) => b.orderDate.compareTo(a.orderDate));

    return Column(
      children: [
        // === КАЛЕНДАРЬ ===
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.shade200,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: TableCalendar<Order>(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            calendarFormat: _calendarFormat,
            startingDayOfWeek: StartingDayOfWeek.monday,
            locale: 'ru_RU',
            
            // Настройки заголовка
            headerStyle: HeaderStyle(
              formatButtonVisible: true,
              titleCentered: true,
              formatButtonShowsNext: false,
              formatButtonDecoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              formatButtonTextStyle: TextStyle(
                color: Theme.of(context).primaryColor,
                fontSize: 12,
              ),
              titleTextStyle: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              leftChevronIcon: Icon(Icons.chevron_left, color: Theme.of(context).primaryColor),
              rightChevronIcon: Icon(Icons.chevron_right, color: Theme.of(context).primaryColor),
            ),
            
            // Стили календаря
            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              weekendTextStyle: TextStyle(color: Colors.red.shade300),
              todayDecoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                shape: BoxShape.circle,
              ),
              markerDecoration: BoxDecoration(
                shape: BoxShape.circle,
              ),
              markersMaxCount: 3,
              markerSize: 6,
              markerMargin: EdgeInsets.symmetric(horizontal: 1),
            ),
            
            // Названия дней недели
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              weekendStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.red.shade300),
            ),
            
            // Переключение формата календаря
            availableCalendarFormats: const {
              CalendarFormat.month: 'Месяц',
              CalendarFormat.twoWeeks: '2 недели',
              CalendarFormat.week: 'Неделя',
            },
            
            onFormatChanged: (format) {
              setState(() {
                _calendarFormat = format;
              });
            },
            
            // Выбор дня
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
              widget.onDaySelected(selectedDay);
            },
            
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
            },
            
            // МАРКЕРЫ (кружочки)
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, date, events) {
                final status = _getDayStatus(date, allOrders);
                
                if (status['total'] == 0) return null;
                
                List<Widget> markers = [];
                
                // Красный кружок - заказы "В работе"
                if (status['inProgress']! > 0) {
                  markers.add(_buildMarker(Colors.red, status['inProgress']!));
                }
                
                // Жёлтый/оранжевый кружок - заказы "Готов"
                if (status['ready']! > 0) {
                  markers.add(_buildMarker(Colors.amber, status['ready']!));
                }
                
                // Зелёный кружок - все выданы
                if (status['completed']! > 0 && 
                    status['inProgress'] == 0 && 
                    status['ready'] == 0) {
                  markers.add(_buildMarker(Colors.green, status['completed']!));
                }
                
                if (markers.isEmpty) return null;
                
                return Positioned(
                  bottom: 1,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: markers,
                  ),
                );
              },
            ),
          ),
        ),
        
        // === ЛЕГЕНДА ===
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: Colors.grey.shade50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem(Colors.red, 'В работе'),
              SizedBox(width: 16),
              _buildLegendItem(Colors.amber, 'Готов'),
              SizedBox(width: 16),
              _buildLegendItem(Colors.green, 'Все выданы'),
            ],
          ),
        ),
        
        Divider(height: 1),
        
        // === ФИЛЬТРЫ ПО СТАТУСУ ===
        Container(
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          color: Theme.of(context).cardColor,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildStatusChip(null, 'Все'),
                SizedBox(width: 8),
                _buildStatusChip(OrderStatus.inProgress, 'В работе'),
                SizedBox(width: 8),
                _buildStatusChip(OrderStatus.ready, 'Готов'),
                SizedBox(width: 8),
                _buildStatusChip(OrderStatus.completed, 'Выдан'),
              ],
            ),
          ),
        ),
        
        Divider(height: 1),
        
        // === ИНФОРМАЦИЯ О ВЫБРАННОМ ДНЕ ===
        Container(
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          color: Colors.grey.shade50,
          child: Row(
            children: [
              Icon(Icons.event, size: 18, color: Theme.of(context).primaryColor),
              SizedBox(width: 8),
              Text(
                DateFormat('d MMMM yyyy (EEEE)', 'ru_RU').format(_selectedDay),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Spacer(),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${filteredOrders.length} заказ(ов)',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        Divider(height: 1),
        
        // === СПИСОК ЗАКАЗОВ ===
        Expanded(
          child: filteredOrders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.event_busy, size: 48, color: Colors.grey.shade400),
                      SizedBox(height: 12),
                      Text(
                        'Нет заказов на эту дату',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                      SizedBox(height: 4),
                      Text(
                        DateFormat('d MMMM', 'ru_RU').format(_selectedDay),
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.only(bottom: 80),
                  itemCount: filteredOrders.length,
                  itemBuilder: (context, index) {
                    final order = filteredOrders[index];
                    return OrderCard(order: order);
                  },
                ),
        ),
      ],
    );
  }

  // Виджет маркера (кружочек)
  Widget _buildMarker(Color color, int count) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 1),
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.4),
            blurRadius: 2,
            spreadRadius: 0.5,
          ),
        ],
      ),
    );
  }

  // Виджет легенды
  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
        ),
      ],
    );
  }

  // Чип фильтра статуса
  Widget _buildStatusChip(OrderStatus? status, String label) {
    final isSelected = _selectedStatusFilter == status;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (bool selected) {
        setState(() {
          _selectedStatusFilter = selected ? status : null;
        });
      },
      selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
      labelStyle: TextStyle(
        color: isSelected ? Theme.of(context).primaryColor : Colors.black,
        fontSize: 12,
      ),
    );
  }
}

bool isSameDay(DateTime? a, DateTime? b) {
  if (a == null || b == null) return false;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

// ===========================================================================
// ОБНОВЛЕННАЯ КАРТОЧКА ЗАКАЗА
// ===========================================================================
class OrderCard extends StatelessWidget {
  final Order order;
  const OrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context, listen: false);
    final currencyFormat = NumberFormat.currency(locale: 'ru_RU', symbol: '₽');

    final totalCost = order.getTotalCost();
    final totalPrice = order.getTotalPrice();
    final profit = order.getProfit();

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OrderEditScreen(initialOrder: order),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Кнопки статуса сверху
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      _StatusButton(
                        icon: Icons.access_time,
                        isSelected: order.status == OrderStatus.inProgress,
                        color: Colors.red,
                        onTap: () => provider.updateOrderStatus(
                            order.id, OrderStatus.inProgress),
                      ),
                      _StatusButton(
                        icon: Icons.check_circle,
                        isSelected: order.status == OrderStatus.ready,
                        color: Colors.amber,
                        onTap: () =>
                            provider.updateOrderStatus(order.id, OrderStatus.ready),
                      ),
                      _StatusButton(
                        icon: Icons.done_all,
                        isSelected: order.status == OrderStatus.completed,
                        color: Colors.green,
                        onTap: () => provider.updateOrderStatus(
                            order.id, OrderStatus.completed),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.delete, color: Colors.red.shade400, size: 20),
                    onPressed: () => _confirmDelete(context, provider),
                  ),
                ],
              ),

              Divider(height: 12),

              // Информация о клиенте
              Row(
                children: [
                  Icon(Icons.person, size: 16, color: Colors.grey),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order.customerName,
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (order.customerPhone != null &&
                      order.customerPhone!.isNotEmpty) ...[
                    Icon(Icons.phone, size: 14, color: Colors.grey),
                    SizedBox(width: 4),
                    Text(order.customerPhone!,
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ],
              ),

              SizedBox(height: 6),
              
              // НОВОЕ: Даты (создания и выдачи)
              Row(
                children: [
                  // Дата создания
                  Icon(Icons.edit_calendar, size: 14, color: Colors.grey.shade400),
                  SizedBox(width: 4),
                  Text(
                    DateFormat('d MMM', 'ru_RU').format(order.orderDate),
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  SizedBox(width: 12),
                  // Дата выдачи
                  Icon(Icons.event, size: 14, color: Theme.of(context).primaryColor),
                  SizedBox(width: 4),
                  Text(
                    'Выдача: ${DateFormat('d MMM', 'ru_RU').format(order.deliveryDate)}',
                    style: TextStyle(
                      fontSize: 11, 
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),

              SizedBox(height: 8),

              // Список изделий
              ...order.items.map((item) => Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${item.productName} x${item.quantity}',
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                        Text(
                          currencyFormat.format(item.getTotalPrice()),
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  )),

              // Украшения и упаковка
              if (order.items
                  .any((i) => i.decorations.isNotEmpty || i.packaging.isNotEmpty))
                Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      ...order.items.expand((i) => i.decorations).map((d) => Chip(
                            label: Text(d.itemName, style: TextStyle(fontSize: 10)),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: Colors.pink.shade50,
                          )),
                      ...order.items.expand((i) => i.packaging).map((p) => Chip(
                            label: Text(p.itemName, style: TextStyle(fontSize: 10)),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: Colors.blue.shade50,
                          )),
                    ],
                  ),
                ),

              SizedBox(height: 8),

              // Итоговая строка
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _MiniStat(
                        label: 'Цена', value: currencyFormat.format(totalPrice)),
                    _MiniStat(
                        label: 'С/с', value: currencyFormat.format(totalCost)),
                    _MiniStat(
                      label: 'Прибыль',
                      value: currencyFormat.format(profit),
                      color: profit >= 0 ? Colors.green : Colors.red,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, PastryProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить заказ?'),
        content: Text('Заказ для "${order.customerName}" будет удален'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text('Отмена')),
          TextButton(
            onPressed: () {
              provider.deleteOrder(order.id);
              Navigator.pop(ctx);
            },
            child: Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
class _StatusButton extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _StatusButton({
    required this.icon,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      iconSize: 22,
      color: isSelected ? color : Colors.grey.shade300,
      onPressed: onTap,
      padding: EdgeInsets.all(4),
      constraints: BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _MiniStat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey)),
        Text(value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            )),
      ],
    );
  }
}

// ===========================================================================
// ВСПОМОГАТЕЛЬНЫЙ КЛАСС ДЛЯ ФОРМЫ ИЗДЕЛИЯ
// ===========================================================================
class OrderItemFormData {
  String? id;
  String? selectedProductId;
  String? selectedInventoryItemId;
  String productName;
  double unitCostFromInventory;
  List<OrderDecorationPackagingItem> decorations;
  List<OrderDecorationPackagingItem> packaging;

  bool isWeightBased;
  double costPerGram;

  late TextEditingController priceController;
  late TextEditingController quantityController;
  late TextEditingController weightKgController;
  late TextEditingController pricePerKgController;

  OrderItemFormData({
    this.id,
    this.selectedProductId,
    this.selectedInventoryItemId,
    this.productName = '',
    this.unitCostFromInventory = 0,
    List<OrderDecorationPackagingItem>? decorations,
    List<OrderDecorationPackagingItem>? packaging,
    double? price,
    int? quantity,
    this.isWeightBased = false,
    this.costPerGram = 0,
    double? weightGrams,
    double? pricePerGram,
  })  : decorations = decorations ?? [],
        packaging = packaging ?? [] {
    priceController = TextEditingController(text: price?.toString() ?? '');
    quantityController = TextEditingController(text: quantity?.toString() ?? '1');
    
    // ИЗМЕНЕНО: Показываем вес только если он реально был (при редактировании)
    // При создании нового заказа — поле пустое
    String weightKgText = '';
    if (weightGrams != null && weightGrams > 0) {
      weightKgText = (weightGrams / 1000).toStringAsFixed(2);
    }
    weightKgController = TextEditingController(text: weightKgText);
    
    // Цена за кг — тоже пустая при создании нового
    String priceKgText = '';
    if (pricePerGram != null && pricePerGram > 0) {
      priceKgText = (pricePerGram * 1000).toStringAsFixed(0);
    }
    pricePerKgController = TextEditingController(text: priceKgText);
  }

  factory OrderItemFormData.fromOrderItem(OrderItem item) {
    return OrderItemFormData(
      id: item.id,
      selectedProductId: item.productId,
      selectedInventoryItemId: item.inventoryItemId,
      productName: item.productName,
      unitCostFromInventory: item.unitCostFromInventory,
      decorations: List.from(item.decorations),
      packaging: List.from(item.packaging),
      price: item.sellingPrice,
      quantity: item.quantity,
      isWeightBased: item.isWeightBased,
      costPerGram: item.costPerGram,
      weightGrams: item.weight,
      pricePerGram: item.pricePerGram,
    );
  }

  double get price => double.tryParse(priceController.text) ?? 0;
  int get quantity => int.tryParse(quantityController.text) ?? 1;
  
  double get weightKg => double.tryParse(weightKgController.text) ?? 0;
  double get weightGrams => weightKg * 1000;
  
  double get pricePerKg => double.tryParse(pricePerKgController.text) ?? 0;
  double get pricePerGram => pricePerKg / 1000;

  String getTabName() {
    if (productName.isEmpty) return 'Новое изделие';
    if (isWeightBased && weightKg > 0) {
      String name = productName.length > 10 
          ? '${productName.substring(0, 10)}...' 
          : productName;
      return '$name (${weightKg.toStringAsFixed(1)} кг)';
    }
    if (productName.length > 15) {
      return '${productName.substring(0, 15)}...';
    }
    return productName;
  }

  void dispose() {
    priceController.dispose();
    quantityController.dispose();
    weightKgController.dispose();
    pricePerKgController.dispose();
  }
}// ОБНОВЛЕННЫЙ ЭКРАН РЕДАКТИРОВАНИЯ ЗАКАЗА
// ===========================================================================
class OrderEditScreen extends StatefulWidget {
  final DateTime? selectedDate;
  final Order? initialOrder;
  const OrderEditScreen({this.selectedDate, this.initialOrder});

  @override
  _OrderEditScreenState createState() => _OrderEditScreenState();
}

class _OrderEditScreenState extends State<OrderEditScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _customerNameController;
  late TextEditingController _customerPhoneController;
  final MaskTextInputFormatter _phoneMaskFormatter = MaskTextInputFormatter(
    mask: '+7 (###) ###-##-##',
    filter: {"#": RegExp(r'[0-9]')},
    type: MaskAutoCompletionType.lazy,
  );

  List<OrderItemFormData> _orderItems = [];
  late TabController _tabController;
  
  // Дата выдачи
  late DateTime _deliveryDate;

  bool get _isEditing => widget.initialOrder != null;
  final currencyFormat = NumberFormat.currency(locale: 'ru_RU', symbol: '₽');

  @override
  void initState() {
    super.initState();
    _customerNameController = TextEditingController(
      text: widget.initialOrder?.customerName ?? '',
    );
    _customerPhoneController = TextEditingController(
      text: widget.initialOrder?.customerPhone != null
          ? _phoneMaskFormatter.maskText(widget.initialOrder!.customerPhone!)
          : '',
    );
    
    // Инициализация даты выдачи
    _deliveryDate = widget.initialOrder?.deliveryDate 
        ?? widget.selectedDate 
        ?? DateTime.now();

    if (_isEditing && widget.initialOrder!.items.isNotEmpty) {
      _orderItems = widget.initialOrder!.items
          .map((item) => OrderItemFormData.fromOrderItem(item))
          .toList();
    } else {
      _orderItems.add(OrderItemFormData());
    }

    _initTabController();
  }

  void _initTabController() {
    _tabController = TabController(
      length: _orderItems.length,
      vsync: this,
    );
  }

  void _addNewItem() {
    setState(() {
      _orderItems.add(OrderItemFormData());
      _tabController.dispose();
      _initTabController();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tabController.animateTo(_orderItems.length - 1);
      });
    });
  }

  void _removeItem(int index) {
    if (_orderItems.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Нельзя удалить единственное изделие')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить изделие?'),
        content: Text(
            'Вы уверены, что хотите удалить "${_orderItems[index].getTabName()}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _orderItems[index].dispose();
                _orderItems.removeAt(index);
                _tabController.dispose();
                _initTabController();
              });
            },
            child: Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _tabController.dispose();
    for (var item in _orderItems) {
      item.dispose();
    }
    super.dispose();
  }

  // Выбор даты выдачи
  Future<void> _pickDeliveryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deliveryDate,
      firstDate: DateTime.now().subtract(Duration(days: 365)),
      lastDate: DateTime.now().add(Duration(days: 365 * 2)),
      locale: Locale('ru', 'RU'),
      helpText: 'ВЫБЕРИТЕ ДАТУ ВЫДАЧИ',
      cancelText: 'ОТМЕНА',
      confirmText: 'ВЫБРАТЬ',
    );
    
    if (picked != null) {
      setState(() {
        _deliveryDate = picked;
      });
    }
  }

  // Создание нового изделия прямо из формы заказа
  Future<void> _createNewProduct(OrderItemFormData itemData) async {
    final provider = Provider.of<PastryProvider>(context, listen: false);
    final countBefore = provider.products.length;
    
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductEditScreen(),
      ),
    );
    
    if (!mounted) return;
    
    final productsAfter = provider.products;
    
    if (productsAfter.length > countBefore) {
      final newProduct = productsAfter.last;
      setState(() {
        itemData.selectedProductId = newProduct.id;
        itemData.productName = newProduct.name;
        itemData.isWeightBased = newProduct.isWeightBased;
        itemData.selectedInventoryItemId = null;
        
        if (newProduct.isWeightBased) {
          itemData.costPerGram = newProduct.getCostPerGram(provider.ingredients);
          itemData.unitCostFromInventory = 0;
        } else {
          itemData.costPerGram = 0;
          itemData.unitCostFromInventory = 0;
        }
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Изделие "${newProduct.name}" создано и выбрано'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Редактировать заказ' : 'Новый заказ'),
        actions: [
          TextButton.icon(
            onPressed: _addNewItem,
            icon: Icon(Icons.add, color: Colors.white),
            label: Text('Изделие', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildCustomerInfoSection(),
            Divider(height: 1),
            _buildItemsTabs(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _orderItems.asMap().entries.map((entry) {
                  return _buildItemForm(entry.key, entry.value, provider);
                }).toList(),
              ),
            ),
            _buildBottomSection(provider),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerInfoSection() {
  return Container(
    padding: EdgeInsets.all(12),
    color: Colors.grey.shade50,
    child: Column(
      children: [
        // Имя и телефон
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: _customerNameController,
                decoration: InputDecoration(
                  labelText: 'Имя клиента',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                  prefixIcon: Icon(Icons.person, size: 20),
                ),
                style: TextStyle(fontSize: 14),
                validator: (v) => v!.isEmpty ? 'Введите имя' : null,
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: _customerPhoneController,
                decoration: InputDecoration(
                  labelText: 'Телефон',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                  prefixIcon: Icon(Icons.phone, size: 20),
                ),
                style: TextStyle(fontSize: 14),
                keyboardType: TextInputType.phone,
                inputFormatters: [_phoneMaskFormatter],
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        
        // === ДАТА ВЫДАЧИ (кликабельная) ===
        InkWell(
          onTap: _pickDeliveryDate,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.event, size: 20, color: Theme.of(context).primaryColor),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Дата выдачи',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                    SizedBox(height: 2),
                    Text(
                      DateFormat('d MMMM yyyy (EEEE)', 'ru_RU').format(_deliveryDate),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                Spacer(),
                Icon(Icons.edit_calendar, size: 18, color: Colors.grey),
              ],
            ),
          ),
        ),
        
        // Дата создания (только для информации при редактировании)
        if (_isEditing) ...[
          SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.access_time, size: 14, color: Colors.grey),
              SizedBox(width: 6),
              Text(
                'Создан: ${DateFormat('d MMM yyyy', 'ru_RU').format(widget.initialOrder!.orderDate)}',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

  Widget _buildItemsTabs() {
    return Container(
      color: Theme.of(context).primaryColor.withOpacity(0.1),
      child: Row(
        children: [
          Expanded(
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: Theme.of(context).primaryColor,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Theme.of(context).primaryColor,
              tabs: _orderItems.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                return Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(item.getTabName()),
                      if (_orderItems.length > 1)
                        Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: InkWell(
                            onTap: () => _removeItem(index),
                            child: Icon(Icons.close, size: 16, color: Colors.grey),
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: Colors.grey.shade300))
            ),
            child: IconButton(
              icon: Icon(Icons.add, color: Theme.of(context).primaryColor),
              tooltip: 'Добавить еще изделие',
              onPressed: _addNewItem,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemForm(
      int index, OrderItemFormData itemData, PastryProvider provider) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProductSelectionRow(itemData, provider),
          SizedBox(height: 12),
          _buildPriceQuantityRow(itemData, provider),
          SizedBox(height: 12),
          _buildDecorationsSection(itemData, provider),
          SizedBox(height: 8),
          _buildPackagingSection(itemData, provider),
          SizedBox(height: 12),
          _buildItemSummary(itemData, provider),
        ],
      ),
    );
  }

  Widget _buildProductSelectionRow(
      OrderItemFormData itemData, PastryProvider provider) {
    
    // Проверяем существование выбранного продукта
    Product? selectedProduct;
    if (itemData.selectedProductId != null) {
      final exists = provider.products.any((p) => p.id == itemData.selectedProductId);
      if (!exists) {
        itemData.selectedProductId = null;
        itemData.productName = '';
        itemData.isWeightBased = false;
      } else {
        selectedProduct = provider.products.firstWhere((p) => p.id == itemData.selectedProductId);
      }
    }

    List<InventoryItem> availableInventory = [];
    if (itemData.selectedProductId != null && !itemData.isWeightBased) {
      availableInventory = provider.getAvailableInventoryForProduct(itemData.selectedProductId!);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Выбор изделия с кнопкой создания
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('products_${provider.products.length}'),
                value: itemData.selectedProductId,
                decoration: InputDecoration(
                  labelText: 'Изделие',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                ),
                isExpanded: true,
                hint: Text('Выберите изделие'),
                items: provider.products.map((p) {
                  return DropdownMenuItem(
                    value: p.id,
                    child: Row(
                      children: [
                        Icon(
                          p.isWeightBased ? Icons.scale : Icons.grid_view,
                          size: 16,
                          color: p.isWeightBased ? Colors.orange : Colors.blue,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(p.name, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    itemData.selectedProductId = value;
                    itemData.selectedInventoryItemId = null;
                    
                    if (value != null) {
                      final product = provider.getProductById(value);
                      itemData.productName = product.name;
                      itemData.isWeightBased = product.isWeightBased;
                      
                      if (product.isWeightBased) {
                        itemData.costPerGram = product.getCostPerGram(provider.ingredients);
                        itemData.unitCostFromInventory = 0;
                      } else {
                        itemData.costPerGram = 0;
                      }
                    } else {
                      itemData.productName = '';
                      itemData.isWeightBased = false;
                      itemData.costPerGram = 0;
                    }
                  });
                },
                validator: (v) => v == null ? 'Выберите изделие' : null,
              ),
            ),
            
            SizedBox(width: 8),
            
            // Кнопка создания нового изделия
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: IconButton(
                icon: Icon(Icons.add, color: Theme.of(context).primaryColor),
                tooltip: 'Создать новое изделие',
                onPressed: () => _createNewProduct(itemData),
              ),
            ),
          ],
        ),
        
        SizedBox(height: 8),
        
        // Подсказка если нет изделий
        if (provider.products.isEmpty)
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber.shade700, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Нет изделий. Нажмите "+", чтобы создать.',
                    style: TextStyle(fontSize: 12, color: Colors.amber.shade800),
                  ),
                ),
              ],
            ),
          ),
        
        // Индикатор типа изделия
        if (selectedProduct != null)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: itemData.isWeightBased ? Colors.orange.shade50 : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  itemData.isWeightBased ? Icons.scale : Icons.grid_view,
                  size: 14,
                  color: itemData.isWeightBased ? Colors.orange : Colors.blue,
                ),
                SizedBox(width: 4),
                Text(
                  itemData.isWeightBased 
                      ? 'Весовое • ${itemData.costPerGram.toStringAsFixed(2)} ₽/г'
                      : 'Штучное',
                  style: TextStyle(
                    fontSize: 11,
                    color: itemData.isWeightBased ? Colors.orange.shade800 : Colors.blue.shade800,
                  ),
                ),
              ],
            ),
          ),
        
        SizedBox(height: 8),
        
        // Для штучного изделия: выбор партии из запасов
        if (itemData.selectedProductId != null && !itemData.isWeightBased)
          DropdownButtonFormField<String?>(
            value: availableInventory.any((i) => i.id == itemData.selectedInventoryItemId) 
                ? itemData.selectedInventoryItemId 
                : null,
            decoration: InputDecoration(
              labelText: 'Партия из запасов',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
            isExpanded: true,
            items: [
              DropdownMenuItem(value: null, child: Text('Выберите партию')),
              ...availableInventory.map((inv) => DropdownMenuItem(
                value: inv.id,
                child: Text(
                  '${inv.availableQuantity} шт - ${DateFormat.yMd('ru_RU').format(inv.productionDate)} (${inv.unitCostAtTimeOfProduction.toStringAsFixed(0)} ₽/шт)',
                  overflow: TextOverflow.ellipsis,
                ),
              )),
            ],
            onChanged: (value) {
              setState(() {
                itemData.selectedInventoryItemId = value;
                if (value != null) {
                  final inv = provider.inventory.firstWhere((i) => i.id == value);
                  itemData.unitCostFromInventory = inv.unitCostAtTimeOfProduction;
                } else {
                  itemData.unitCostFromInventory = 0;
                }
              });
            },
            validator: (v) => !itemData.isWeightBased && v == null ? 'Выберите партию' : null,
          ),
        
        // Для весового изделия: информация
        if (itemData.selectedProductId != null && itemData.isWeightBased)
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.grey),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Весовое изделие готовится под заказ.\nУкажите вес ниже.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPriceQuantityRow(
      OrderItemFormData itemData, PastryProvider provider) {
    
    if (itemData.isWeightBased) {
      // Для весового изделия
      final costPerKg = itemData.costPerGram * 1000;
      
      double baseWeightGrams = 0;
      if (itemData.selectedProductId != null) {
        final product = provider.getProductById(itemData.selectedProductId!);
        baseWeightGrams = product.getBaseWeight();
      }
      final baseWeightKg = baseWeightGrams / 1000;
      
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: itemData.weightKgController,
                  decoration: InputDecoration(
                    labelText: 'Вес (кг)',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    isDense: true,
                    prefixIcon: Icon(Icons.scale, size: 20),
                    suffixText: 'кг',
                    hintText: baseWeightKg > 0 
                        ? 'напр. ${baseWeightKg.toStringAsFixed(1)}' 
                        : '1.5',
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    if (v!.isEmpty) return 'Введите вес';
                    final weight = double.tryParse(v);
                    if (weight == null || weight <= 0) return 'Вес > 0';
                    return null;
                  },
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: itemData.pricePerKgController,
                  decoration: InputDecoration(
                    labelText: 'Цена за 1 кг, ₽',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    isDense: true,
                    suffixText: '₽/кг',
                    hintText: '2500',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    if (v!.isEmpty) return 'Цена';
                    return null;
                  },
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                if (baseWeightGrams > 0)
                  Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Базовый вес рецепта:', 
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        Text(
                          '${baseWeightGrams.toStringAsFixed(0)} г (${baseWeightKg.toStringAsFixed(2)} кг)',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Себестоимость за 1 кг:', 
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                    Text(
                      '${costPerKg.toStringAsFixed(2)} ₽',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                
                if (itemData.weightKg > 0) ...[
                  Divider(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Вес:', style: TextStyle(fontSize: 12)),
                      Text(
                        '${itemData.weightGrams.toStringAsFixed(0)} г (${itemData.weightKg.toStringAsFixed(2)} кг)',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Себестоимость:', style: TextStyle(fontSize: 12)),
                      Text(
                        '${(itemData.costPerGram * itemData.weightGrams).toStringAsFixed(2)} ₽',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Цена продажи:', style: TextStyle(fontSize: 12)),
                      Text(
                        '${(itemData.pricePerKg * itemData.weightKg).toStringAsFixed(2)} ₽',
                        style: TextStyle(
                          fontSize: 12, 
                          fontWeight: FontWeight.bold, 
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    } else {
      // Для штучного изделия
      return Row(
        children: [
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: itemData.priceController,
              decoration: InputDecoration(
                labelText: 'Цена, ₽',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              validator: (v) => v!.isEmpty ? 'Цена' : null,
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: itemData.quantityController,
              decoration: InputDecoration(
                labelText: 'Кол-во',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              validator: (v) {
                if (v!.isEmpty) return 'Кол-во';
                final qty = int.tryParse(v);
                if (qty == null || qty <= 0) return '>0';
                if (itemData.selectedInventoryItemId != null) {
                  final inv = provider.inventory.firstWhere(
                    (i) => i.id == itemData.selectedInventoryItemId,
                    orElse: () => InventoryItem(
                      id: '',
                      productId: '',
                      productName: '',
                      quantity: 0,
                      productionDate: DateTime.now(),
                      unitCostAtTimeOfProduction: 0,
                    ),
                  );
                  if (qty > inv.availableQuantity) return 'Макс: ${inv.availableQuantity}';
                }
                return null;
              },
            ),
          ),
        ],
      );
    }
  }

  Widget _buildDecorationsSection(
      OrderItemFormData itemData, PastryProvider provider) {
    return _buildAddonsSection(
      title: 'Украшения',
      items: itemData.decorations,
      onAdd: () =>
          _addAddon(itemData.decorations, IngredientType.decoration, provider),
      onRemove: (item) => setState(() => itemData.decorations.remove(item)),
      quantity: itemData.quantity,
    );
  }

  Widget _buildPackagingSection(
      OrderItemFormData itemData, PastryProvider provider) {
    return _buildAddonsSection(
      title: 'Упаковка',
      items: itemData.packaging,
      onAdd: () =>
          _addAddon(itemData.packaging, IngredientType.packaging, provider),
      onRemove: (item) => setState(() => itemData.packaging.remove(item)),
      quantity: itemData.quantity,
    );
  }

  Widget _buildAddonsSection({
    required String title,
    required List<OrderDecorationPackagingItem> items,
    required VoidCallback onAdd,
    required Function(OrderDecorationPackagingItem) onRemove,
    required int quantity,
  }) {
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
              InkWell(
                onTap: onAdd,
                child: Row(
                  children: [
                    Icon(Icons.add,
                        size: 16, color: Theme.of(context).primaryColor),
                    Text('Добавить',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).primaryColor,
                        )),
                  ],
                ),
              ),
            ],
          ),
          if (items.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('Не добавлено',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
            )
          else
            ...items.map((item) => Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${item.itemName} (${item.quantity.toStringAsFixed(0)})',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(
                        currencyFormat
                            .format(item.itemPriceAtTime * item.quantity * quantity),
                        style: TextStyle(fontSize: 12),
                      ),
                      InkWell(
                        onTap: () => onRemove(item),
                        child: Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.close,
                              size: 14, color: Colors.red.shade300),
                        ),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  Future<void> _addAddon(
    List<OrderDecorationPackagingItem> list,
    IngredientType type,
    PastryProvider provider,
  ) async {
    final result = await showDialog<OrderDecorationPackagingItem>(
      context: context,
      builder: (ctx) => AddDecorationPackagingDialog(
        title: type == IngredientType.decoration
            ? 'Добавить украшение'
            : 'Добавить упаковку',
        type: type,
      ),
    );
    if (result != null) {
      setState(() => list.add(result));
    }
  }

  Widget _buildItemSummary(OrderItemFormData itemData, PastryProvider provider) {
    double totalPrice;
    double totalCost;
    
    if (itemData.isWeightBased) {
      totalPrice = itemData.pricePerGram * itemData.weightGrams;
      totalCost = itemData.costPerGram * itemData.weightGrams;
    } else {
      totalPrice = itemData.price * itemData.quantity;
      totalCost = itemData.unitCostFromInventory * itemData.quantity;
    }

    for (var d in itemData.decorations) {
      double decoCost = d.itemPriceAtTime * d.quantity;
      if (!itemData.isWeightBased) decoCost *= itemData.quantity;
      totalCost += decoCost;
    }
    for (var p in itemData.packaging) {
      double packCost = p.itemPriceAtTime * p.quantity;
      if (!itemData.isWeightBased) packCost *= itemData.quantity;
      totalCost += packCost;
    }

    final profit = totalPrice - totalCost;

    return Container(
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: itemData.isWeightBased ? Colors.orange.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          if (itemData.isWeightBased && itemData.weightKg > 0)
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.scale, size: 16, color: Colors.orange),
                  SizedBox(width: 4),
                  Text(
                    'Вес: ${itemData.weightKg.toStringAsFixed(2)} кг (${itemData.weightGrams.toStringAsFixed(0)} г)',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMiniStat('Цена', currencyFormat.format(totalPrice)),
              _buildMiniStat('С/с', currencyFormat.format(totalCost)),
              _buildMiniStat(
                'Прибыль',
                currencyFormat.format(profit),
                color: profit >= 0 ? Colors.green : Colors.red,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, {Color? color}) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey)),
        Text(value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            )),
      ],
    );
  }

  Widget _buildBottomSection(PastryProvider provider) {
    double totalPrice = 0;
    double totalCost = 0;

    for (var item in _orderItems) {
      if (item.isWeightBased) {
        totalPrice += item.pricePerGram * item.weightGrams;
        totalCost += item.costPerGram * item.weightGrams;
      } else {
        final qty = item.quantity;
        totalPrice += item.price * qty;
        totalCost += item.unitCostFromInventory * qty;
      }
      
      for (var d in item.decorations) {
        double decoCost = d.itemPriceAtTime * d.quantity;
        if (!item.isWeightBased) decoCost *= item.quantity;
        totalCost += decoCost;
      }
      for (var p in item.packaging) {
        double packCost = p.itemPriceAtTime * p.quantity;
        if (!item.isWeightBased) packCost *= item.quantity;
        totalCost += packCost;
      }
    }

    final profit = totalPrice - totalCost;

    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade300,
            blurRadius: 4,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildTotalStat('Изделий', '${_orderItems.length}', Icons.cake),
                _buildTotalStat('Итого', currencyFormat.format(totalPrice), Icons.payments),
                _buildTotalStat(
                  'Прибыль',
                  currencyFormat.format(profit),
                  Icons.trending_up,
                  color: profit >= 0 ? Colors.green : Colors.red,
                ),
              ],
            ),
            SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: _saveOrder,
                child: Text(
                  _isEditing ? 'Сохранить изменения' : 'Создать заказ',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalStat(String label, String value, IconData icon,
      {Color? color}) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color ?? Colors.grey),
        SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey)),
        Text(value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            )),
      ],
    );
  }

  void _saveOrder() {
  if (!_formKey.currentState!.validate()) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Заполните все обязательные поля')),
    );
    return;
  }

  final provider = Provider.of<PastryProvider>(context, listen: false);

  // Проверяем все позиции
  for (var item in _orderItems) {
    if (item.selectedProductId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Выберите изделие для всех позиций')),
      );
      return;
    }
    
    if (!item.isWeightBased && item.selectedInventoryItemId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Выберите партию для штучных изделий')),
      );
      return;
    }
    
    if (item.isWeightBased && item.weightKg <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Укажите вес для весовых изделий')),
      );
      return;
    }
  }

  final orderItems = _orderItems.map((formData) {
    return OrderItem(
      id: formData.id ?? Random().nextInt(100000).toString(),
      productId: formData.selectedProductId!,
      productName: formData.productName,
      inventoryItemId: formData.selectedInventoryItemId,
      unitCostFromInventory: formData.unitCostFromInventory,
      quantity: formData.quantity,
      sellingPrice: formData.price,
      decorations: List.from(formData.decorations),
      packaging: List.from(formData.packaging),
      isWeightBased: formData.isWeightBased,
      weight: formData.isWeightBased ? formData.weightGrams : null,
      costPerGram: formData.costPerGram,
      pricePerGram: formData.pricePerGram,
    );
  }).toList();

  final order = Order(
    id: _isEditing ? widget.initialOrder!.id : '',
    customerName: _customerNameController.text.trim(),
    customerPhone: _customerPhoneController.text.isEmpty
        ? null
        : _customerPhoneController.text,
    orderDate: _isEditing 
        ? widget.initialOrder!.orderDate 
        : DateTime.now(),  // Дата создания = сейчас
    deliveryDate: _deliveryDate,  // НОВОЕ: Дата выдачи
    status: _isEditing ? widget.initialOrder!.status : OrderStatus.inProgress,
    items: orderItems,
  );

  if (_isEditing) {
    provider.updateOrder(order);
  } else {
    provider.addOrder(order);
  }

  Navigator.pop(context);
}
}
// --- ЭКРАН ИЗДЕЛИЙ ---
class ProductsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context);
    final currencyFormat = NumberFormat.currency(locale: 'ru_RU', symbol: '₽');

    return provider.products.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cake_outlined, size: 64, color: Colors.grey.shade400),
                SizedBox(height: 16),
                Text(
                  'У вас пока нет изделий',
                  style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                ),
                SizedBox(height: 8),
                Text(
                  'Нажмите "+", чтобы добавить',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          )
        : ListView.builder(
            padding: EdgeInsets.all(8),
            itemCount: provider.products.length,
            itemBuilder: (context, index) {
              final product = provider.products[index];
              final totalCost = product.getCost(provider.ingredients);
              
              return Card(
                elevation: 2,
                margin: EdgeInsets.symmetric(vertical: 8),
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProductEditScreen(initialProduct: product),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // === ЗАГОЛОВОК С НАЗВАНИЕМ И ТИПОМ ===
                        Row(
                          children: [
                            // Иконка типа изделия
                            Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: product.isWeightBased 
                                    ? Colors.orange.shade50 
                                    : Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                product.isWeightBased ? Icons.scale : Icons.grid_view,
                                color: product.isWeightBased ? Colors.orange : Colors.blue,
                                size: 24,
                              ),
                            ),
                            SizedBox(width: 12),
                            // Название и тип
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: product.isWeightBased 
                                          ? Colors.orange.shade100 
                                          : Colors.blue.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      product.isWeightBased ? 'Весовое' : 'Штучное',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: product.isWeightBased 
                                            ? Colors.orange.shade800 
                                            : Colors.blue.shade800,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Кнопки действий
                            _buildActionButtons(context, product, provider),
                          ],
                        ),
                        
                        SizedBox(height: 12),
                        Divider(height: 1),
                        SizedBox(height: 12),
                        
                        // === ИНФОРМАЦИЯ О СЕБЕСТОИМОСТИ ===
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              // Себестоимость рецепта
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.receipt_long, size: 16, color: Colors.grey),
                                      SizedBox(width: 6),
                                      Text(
                                        'Себестоимость рецепта:',
                                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    currencyFormat.format(totalCost),
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              
                              SizedBox(height: 8),
                              
                              // Для весового или штучного
                              if (product.isWeightBased) ...[
  // Весовое изделие
  Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Row(
        children: [
          Icon(Icons.scale, size: 16, color: Colors.orange),
          SizedBox(width: 6),
          Text(
            'Базовый вес:',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
        ],
      ),
      Text(
        '${product.getBaseWeight().toStringAsFixed(0)} г',  // ✅ getBaseWeight()
        style: TextStyle(fontSize: 14),
      ),
    ],
  ),
  SizedBox(height: 8),
  Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Row(
        children: [
          Icon(Icons.monetization_on, size: 16, color: Colors.orange),
          SizedBox(width: 6),
          Text(
            'Себестоимость за 1 кг:',
            style: TextStyle(fontSize: 13, color: Colors.orange.shade700),
          ),
        ],
      ),
      Text(
        '${(product.getCostPerGram(provider.ingredients) * 1000).toStringAsFixed(2)} ₽',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.orange,
        ),
      ),
    ],
  ),
  SizedBox(height: 4),
  Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        '      Себестоимость за 1 г:',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      ),
      Text(
        '${product.getCostPerGram(provider.ingredients).toStringAsFixed(4)} ₽',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
      ),
    ],
  ),
]
else ...[
                                // Штучное изделие
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.numbers, size: 16, color: Colors.blue),
                                        SizedBox(width: 6),
                                        Text(
                                          'Количество из рецепта:',
                                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      '${product.producedQuantity} шт',
                                      style: TextStyle(fontSize: 14),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.monetization_on, size: 16, color: Colors.blue),
                                        SizedBox(width: 6),
                                        Text(
                                          'Себестоимость за 1 шт:',
                                          style: TextStyle(fontSize: 13, color: Colors.blue.shade700),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      currencyFormat.format(product.getUnitCost(provider.ingredients)),
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        
                        // === СПИСОК ИНГРЕДИЕНТОВ (компактный) ===
                        if (product.ingredients.isNotEmpty) ...[
                          SizedBox(height: 12),
                          Text(
                            'Ингредиенты:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: product.ingredients.map((comp) {
                              final ingredient = provider.getIngredientById(comp.ingredientId);
                              return Container(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${ingredient.name} (${comp.quantity.toStringAsFixed(0)} г)',
                                  style: TextStyle(fontSize: 11),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
  }

  Widget _buildActionButtons(BuildContext context, Product product, PastryProvider provider) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Кнопка "Добавить в запасы" - только для штучных изделий
        if (!product.isWeightBased)
          IconButton(
            icon: Icon(Icons.inventory, color: Colors.blue.shade600),
            tooltip: 'Добавить в запасы',
            onPressed: () => _addToInventoryDialog(context, product, provider),
            constraints: BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.all(4),
          ),
        
        // Кнопка "Редактировать"
        IconButton(
          icon: Icon(Icons.edit, color: Colors.grey.shade600),
          tooltip: 'Редактировать',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProductEditScreen(initialProduct: product),
            ),
          ),
          constraints: BoxConstraints(minWidth: 36, minHeight: 36),
          padding: EdgeInsets.all(4),
        ),
        
        // Кнопка "Удалить"
        IconButton(
          icon: Icon(Icons.delete, color: Colors.red.shade400),
          tooltip: 'Удалить',
          onPressed: () => _confirmDelete(context, product, provider),
          constraints: BoxConstraints(minWidth: 36, minHeight: 36),
          padding: EdgeInsets.all(4),
        ),
      ],
    );
  }

  void _confirmDelete(BuildContext context, Product product, PastryProvider provider) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.red),
              SizedBox(width: 8),
              Text('Подтвердите удаление'),
            ],
          ),
          content: Text('Удалить изделие "${product.name}"?\n\nЭто действие нельзя отменить.'),
          actions: <Widget>[
            TextButton(
              child: Text('Отмена'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: Text('Удалить'),
              onPressed: () {
                provider.deleteProduct(product.id);
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Изделие "${product.name}" удалено'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _addToInventoryDialog(BuildContext context, Product product, PastryProvider provider) {
    // Проверяем, что это штучное изделие
    if (product.isWeightBased) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Весовые изделия нельзя добавить в запасы')),
      );
      return;
    }

    if (product.producedQuantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: Неверное количество изделия')),
      );
      return;
    }

    DateTime selectedDate = DateTime.now();
    TextEditingController quantityController =
        TextEditingController(text: product.producedQuantity.toString());
    final currencyFormat = NumberFormat.currency(locale: 'ru_RU', symbol: '₽');
    final unitCost = product.getUnitCost(provider.ingredients);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            int quantity = int.tryParse(quantityController.text) ?? 0;
            double totalCost = unitCost * quantity;

            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.inventory, color: Colors.blue),
                  SizedBox(width: 8),
                  Expanded(child: Text('Добавить в запасы')),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Информация об изделии
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Себестоимость: ${currencyFormat.format(unitCost)} / шт',
                            style: TextStyle(fontSize: 13, color: Colors.blue.shade700),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),
                    
                    // Количество
                    TextField(
                      controller: quantityController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Количество',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.numbers),
                        suffixText: 'шт',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    SizedBox(height: 12),
                    
                    // Дата изготовления
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2101),
                          locale: Locale('ru', 'RU'),
                        );
                        if (picked != null) {
                          setState(() {
                            selectedDate = picked;
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Дата изготовления',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(DateFormat('d MMMM yyyy', 'ru_RU').format(selectedDate)),
                      ),
                    ),
                    SizedBox(height: 16),
                    
                    // Итоговая стоимость
                    if (quantity > 0)
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Общая себестоимость:'),
                            Text(
                              currencyFormat.format(totalCost),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Отмена'),
                ),
                ElevatedButton.icon(
                  icon: Icon(Icons.add),
                  label: Text('Добавить'),
                  onPressed: quantity > 0
                      ? () {
                          try {
                            provider.addProductToInventory(
                              product.id,
                              quantity,
                              selectedDate,
                            );
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Добавлено в запасы: ${product.name} ($quantity шт)',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Ошибка: ${e.toString()}'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      : null,
                ),
              ],
            );
          },
        );
      },
    );
  }
}
// --- ЭКРАН РЕДАКТИРОВАНИЯ ИЗДЕЛИЯ ---
class ProductEditScreen extends StatefulWidget {
  final Product? initialProduct;
  const ProductEditScreen({this.initialProduct});
  @override
  _ProductEditScreenState createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _producedQuantityController;
  late List<RecipeComponent> _ingredients;
  late bool _isWeightBased;

  bool get _isEditing => widget.initialProduct != null;
  
  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialProduct?.name ?? '');
    _producedQuantityController = TextEditingController(
        text: widget.initialProduct?.producedQuantity.toString() ?? '1');
    _ingredients = widget.initialProduct?.ingredients
            .map((c) => RecipeComponent(ingredientId: c.ingredientId, quantity: c.quantity))
            .toList() ?? [];
    _isWeightBased = widget.initialProduct?.isWeightBased ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _producedQuantityController.dispose();
    super.dispose();
  }

  void _addComponent(List<RecipeComponent> componentList) async {
    final result = await showDialog<RecipeComponent>(
        context: context, builder: (context) => AddComponentDialog());
    if (result != null) {
      setState(() => componentList.add(result));
    }
  }

  void _removeComponent(List<RecipeComponent> componentList, RecipeComponent component) {
    setState(() {
      componentList.remove(component);
    });
  }

  // Вычисляем базовый вес из ингредиентов
  double _calculateBaseWeight() {
    double total = 0;
    for (var component in _ingredients) {
      total += component.quantity;
    }
    return total;
  }

  Widget _buildComponentList(String title, List<RecipeComponent> components, PastryProvider provider) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        IconButton(
            icon: Icon(Icons.add_circle_outline, color: Theme.of(context).primaryColor),
            onPressed: () => _addComponent(components)),
      ]),
      if (components.isEmpty)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text('  Компоненты не добавлены', style: TextStyle(color: Colors.grey))),
      ...components.asMap().entries.map((entry) {
        int idx = entry.key;
        RecipeComponent c = entry.value;
        final ingredient = provider
            .getIngredientsByType(IngredientType.ingredient)
            .firstWhere((ing) => ing.id == c.ingredientId,
                orElse: () => Ingredient(
                    id: 'not_found',
                    name: 'Не найден',
                    price: 0,
                    packageSize: 0,
                    type: IngredientType.ingredient));
        return ListTile(
          key: ValueKey('$title-$idx'),
          title: Text(ingredient.name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${c.quantity.toStringAsFixed(0)} г', style: TextStyle(fontSize: 12)),
              IconButton(
                  icon: Icon(Icons.remove_circle_outline, color: Colors.red.shade300, size: 18),
                  onPressed: () => _removeComponent(components, c),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minHeight: 24, minWidth: 24)),
            ],
          ),
        );
      }).toList(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context);
    
    // Вычисляем базовый вес из ингредиентов
    final baseWeight = _calculateBaseWeight();
    
    // Расчёт себестоимости
    double totalCost = Product(
      id: '',
      name: '',
      ingredients: _ingredients,
      producedQuantity: int.tryParse(_producedQuantityController.text) ?? 1,
      isWeightBased: _isWeightBased,
    ).getCost(provider.ingredients);
    
    double unitCost = 0;
    double costPerGram = 0;
    double costPerKg = 0;
    
    if (_isWeightBased) {
      costPerGram = baseWeight > 0 ? totalCost / baseWeight : 0;
      costPerKg = costPerGram * 1000;
    } else {
      int producedQuantity = int.tryParse(_producedQuantityController.text) ?? 1;
      unitCost = producedQuantity > 0 ? totalCost / producedQuantity : 0;
    }

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Редактировать изделие' : 'Новое изделие')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Название изделия',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
                ),
                validator: (value) => value!.isEmpty ? 'Введите название' : null,
              ),
              SizedBox(height: 16),
              
              // === ПЕРЕКЛЮЧАТЕЛЬ ТИПА ИЗДЕЛИЯ ===
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isWeightBased ? Colors.orange.shade50 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isWeightBased ? Colors.orange.shade200 : Colors.blue.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isWeightBased ? Icons.scale : Icons.grid_view,
                          color: _isWeightBased ? Colors.orange : Colors.blue,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Тип изделия',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _isWeightBased = false),
                            child: Container(
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: !_isWeightBased ? Colors.blue : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.grid_view,
                                    color: !_isWeightBased ? Colors.white : Colors.grey,
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Штучное',
                                    style: TextStyle(
                                      color: !_isWeightBased ? Colors.white : Colors.grey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    'Капкейки, пирожные',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: !_isWeightBased ? Colors.white70 : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _isWeightBased = true),
                            child: Container(
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _isWeightBased ? Colors.orange : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.scale,
                                    color: _isWeightBased ? Colors.white : Colors.grey,
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Весовое',
                                    style: TextStyle(
                                      color: _isWeightBased ? Colors.white : Colors.grey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    'Торты, рулеты',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: _isWeightBased ? Colors.white70 : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              
              // === ПОЛЯ В ЗАВИСИМОСТИ ОТ ТИПА ===
              if (_isWeightBased) ...[
                // Для весового изделия - только информация
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, size: 18, color: Colors.orange),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Базовый вес рецепта рассчитывается автоматически из суммы всех ингредиентов.',
                              style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                            ),
                          ),
                        ],
                      ),
                      if (baseWeight > 0) ...[
                        SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.scale, size: 20, color: Colors.orange.shade700),
                            SizedBox(width: 8),
                            Text(
                              'Базовый вес: ${baseWeight.toStringAsFixed(0)} г (${(baseWeight / 1000).toStringAsFixed(2)} кг)',
                              style: TextStyle(
                                fontSize: 14, 
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ] else ...[
                // Для штучного изделия
                TextFormField(
                  controller: _producedQuantityController,
                  decoration: InputDecoration(
                    labelText: 'Количество изготовленных (шт)',
                    helperText: 'Сколько штук получается из рецепта',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.numbers),
                    suffixText: 'шт',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    if (_isWeightBased) return null; // Не валидируем для весовых
                    if (value!.isEmpty) return 'Введите количество';
                    final quantity = int.tryParse(value);
                    if (quantity == null || quantity <= 0) return 'Количество должно быть больше 0';
                    return null;
                  },
                ),
              ],
              
              SizedBox(height: 20),
              _buildComponentList('Ингредиенты', _ingredients, provider),
              Divider(height: 30),
              
              // === ИТОГОВАЯ СЕБЕСТОИМОСТЬ ===
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Себестоимость рецепта:', style: TextStyle(fontSize: 14)),
                        Text('${totalCost.toStringAsFixed(2)} ₽', 
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Divider(),
                    if (_isWeightBased) ...[
                      // Для весового
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Базовый вес рецепта:', style: TextStyle(fontSize: 14)),
                          Text('${baseWeight.toStringAsFixed(0)} г', 
                              style: TextStyle(fontSize: 14)),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Себестоимость за 1 кг:', 
                              style: TextStyle(fontSize: 14, color: Colors.orange.shade800)),
                          Text('${costPerKg.toStringAsFixed(2)} ₽/кг', 
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange)),
                        ],
                      ),
                      SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Себестоимость за 1 г:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          Text('${costPerGram.toStringAsFixed(4)} ₽/г', 
                              style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                      if (_ingredients.isEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Добавьте ингредиенты для расчёта',
                            style: TextStyle(fontSize: 12, color: Colors.red),
                          ),
                        ),
                    ] else ...[
                      // Для штучного
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Себестоимость за 1 шт:', 
                              style: TextStyle(fontSize: 14, color: Colors.blue.shade800)),
                          Text('${unitCost.toStringAsFixed(2)} ₽', 
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              
              SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 16)),
                child: Text('Сохранить'),
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    // Для весовых изделий проверяем наличие ингредиентов
                    if (_isWeightBased && _ingredients.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Добавьте ингредиенты для весового изделия')),
                      );
                      return;
                    }
                    
                    final product = Product(
                      id: _isEditing ? widget.initialProduct!.id : '',
                      name: _nameController.text,
                      ingredients: _ingredients,
                      producedQuantity: int.tryParse(_producedQuantityController.text) ?? 1,
                      isWeightBased: _isWeightBased,
                    );
                    if (_isEditing) {
                      provider.updateProduct(product);
                    } else {
                      provider.addProduct(product);
                    }
                    Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}// --- СПРАВОЧНИК ---
class IngredientsMainScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          bottom: TabBar(
            tabs: [
              Tab(text: 'Ингредиенты'),
              Tab(text: 'Украшения'),
              Tab(text: 'Упаковка'),
            ],
          ),
          title: Text('Справочник'),
        ),
        body: TabBarView(
          children: [
            IngredientsListScreen(type: IngredientType.ingredient),
            IngredientsListScreen(type: IngredientType.decoration),
            IngredientsListScreen(type: IngredientType.packaging),
          ],
        ),
      ),
    );
  }
}

class IngredientsListScreen extends StatelessWidget {
  final IngredientType type;
  const IngredientsListScreen({required this.type});
  String _getTypeName(IngredientType type) {
    switch (type) {
      case IngredientType.ingredient:
        return 'Ингредиенты';
      case IngredientType.decoration:
        return 'Украшения';
      case IngredientType.packaging:
        return 'Упаковка';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context);
    final ingredients = provider.getIngredientsByType(type);

    return ingredients.isEmpty
        ? Center(
            child: Text(
                '${_getTypeName(type)} пусты.\nНажмите "+", чтобы добавить.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey)))
        : ListView.builder(
            padding: EdgeInsets.all(8),
            itemCount: ingredients.length,
            itemBuilder: (context, index) {
              final ing = ingredients[index];
              return Card(
                  elevation: 2,
                  margin: EdgeInsets.symmetric(vertical: 8),
                  child: ListTile(
                    title: Text(ing.name),
                    subtitle: Text(
                        '${ing.price} ₽ / ${ing.packageSize.toStringAsFixed(0)} г/шт'),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit, color: Colors.grey.shade600),
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => IngredientEditScreen(
                                      initialIngredient: ing, type: ing.type))),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, color: Colors.red.shade400),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: Text('Подтвердите удаление'),
                                  content: Text('Удалить "${ing.name}"?'),
                                  actions: <Widget>[
                                    TextButton(
                                      child: Text('Отмена'),
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                      },
                                    ),
                                    TextButton(
                                      child: Text('Удалить'),
                                      onPressed: () {
                                        provider.deleteIngredient(ing.id);
                                        Navigator.of(context).pop();
                                      },
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ));
            },
          );
  }
}

class IngredientEditScreen extends StatefulWidget {
  final Ingredient? initialIngredient;
  final IngredientType type;
  const IngredientEditScreen({this.initialIngredient, required this.type});

  @override
  _IngredientEditScreenState createState() => _IngredientEditScreenState();
}

class _IngredientEditScreenState extends State<IngredientEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  late TextEditingController _packageSizeController;
  late IngredientType _ingredientType;

  bool get _isEditing => widget.initialIngredient != null;
  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.initialIngredient?.name ?? '');
    _priceController = TextEditingController(
        text: widget.initialIngredient?.price.toString() ?? '');
    _packageSizeController = TextEditingController(
        text: widget.initialIngredient?.packageSize.toString() ?? '');
    _ingredientType = widget.initialIngredient?.type ?? widget.type;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _packageSizeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Редактировать' : 'Новый')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                      labelText: 'Название', border: OutlineInputBorder()),
                  validator: (value) =>
                      value!.isEmpty ? 'Введите название' : null),
              SizedBox(height: 16),
              TextFormField(
                  controller: _priceController,
                  decoration: InputDecoration(
                      labelText: 'Цена за упаковку, ₽',
                      border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  validator: (value) => value!.isEmpty ? 'Введите цену' : null),
              SizedBox(height: 16),
              TextFormField(
                  controller: _packageSizeController,
                  decoration: InputDecoration(
                      labelText: 'Вес/кол-во в упаковке (г/шт)',
                      border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  validator: (value) => value!.isEmpty ? 'Введите вес' : null),
              SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 16)),
                child: Text('Сохранить'),
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    final ingredient = Ingredient(
                        id: _isEditing ? widget.initialIngredient!.id : '',
                        name: _nameController.text,
                        price: double.tryParse(_priceController.text) ?? 0,
                        packageSize:
                            double.tryParse(_packageSizeController.text) ?? 0,
                        type: _ingredientType);
                    final provider =
                        Provider.of<PastryProvider>(context, listen: false);
                    if (_isEditing) {
                      provider.updateIngredient(ingredient);
                    } else {
                      provider.addIngredient(ingredient);
                    }
                    Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- ЭКРАН ЗАПАСОВ ---
class InventoryScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context);
    final currencyFormat = NumberFormat.currency(locale: 'ru_RU', symbol: '₽');

    final availableInventory =
        provider.inventory.where((item) => item.availableQuantity > 0).toList();
    return availableInventory.isEmpty
        ? Center(
            child: Text(
                'Запасы пусты.\nСоздайте изделие и добавьте его в запасы.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey)))
        : ListView.builder(
            padding: EdgeInsets.all(8),
            itemCount: availableInventory.length,
            itemBuilder: (context, index) {
              final item = availableInventory[index];
              return Card(
                elevation: 2,
                margin: EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  title: Text(item.productName,
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Количество: ${item.quantity} шт'),
                      Text('Доступно: ${item.availableQuantity} шт'),
                      Text(
                          'Дата изготовления: ${DateFormat.yMd('ru_RU').format(item.productionDate)}'),
                      Text(
                          'Себестоимость единицы: ${currencyFormat.format(item.unitCostAtTimeOfProduction)}'),
                    ],
                  ),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      IconButton(
                        icon: Icon(Icons.delete, color: Colors.red.shade400),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: Text('Подтвердите удаление'),
                                content: Text(
                                    'Удалить запись о запасе "${item.productName}"?'),
                                actions: <Widget>[
                                  TextButton(
                                    child: Text('Отмена'),
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                    },
                                  ),
                                  TextButton(
                                    child: Text('Удалить'),
                                    onPressed: () {
                                      provider.deleteInventoryItem(item.id);
                                      Navigator.of(context).pop();
                                    },
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
  }
}

// --- СТАТИСТИКА ---
class StatisticsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context);
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final startOfMonth = DateTime(now.year, now.month, 1);
    final startOfYear = DateTime(now.year, 1, 1);
    final statsWeek = provider.getStatisticsForPeriod(startOfWeek, now);
    final statsMonth = provider.getStatisticsForPeriod(startOfMonth, now);
    final statsYear = provider.getStatisticsForPeriod(startOfYear, now);
    final statsAllTime = provider.getStatistics();

    final currencyFormat = NumberFormat.currency(locale: 'ru_RU', symbol: '₽');
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Неделя'),
              Tab(text: 'Месяц'),
              Tab(text: 'Год'),
              Tab(text: 'Всё время'),
            ],
          ),
          title: Text('Статистика'),
        ),
        body: TabBarView(
          children: [
            _buildStatsTabContent(context, statsWeek, currencyFormat, 'за неделю'),
            _buildStatsTabContent(
                context, statsMonth, currencyFormat, 'за месяц'),
            _buildStatsTabContent(context, statsYear, currencyFormat, 'за год'),
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Статистика (выполненные заказы)',
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center),
                      SizedBox(height: 24),
                      StatisticCard(
                          title: 'Полученная прибыль',
                          value:
                              currencyFormat.format(statsAllTime['profit'] ?? 0),
                          color: Colors.green),
                      SizedBox(height: 16),
                      StatisticCard(
                          title: 'Общая выручка',
                          value:
                              currencyFormat.format(statsAllTime['revenue'] ?? 0),
                          color: Colors.blue),
                      SizedBox(height: 16),
                      StatisticCard(
                          title: 'Общие затраты',
                          value: currencyFormat.format(statsAllTime['cost'] ?? 0),
                          color: Colors.orange),
                      SizedBox(height: 16),
                      StatisticCard(
                          title: 'Выполнено заказов',
                          value:
                              (statsAllTime['orderCount'] ?? 0).toInt().toString(),
                          color: Colors.grey),
                    ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsTabContent(BuildContext context, Map<String, double> stats,
      NumberFormat currencyFormat, String periodLabel) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Статистика $periodLabel',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center),
            SizedBox(height: 24),
            StatisticCard(
              title: 'Прибыль',
              value: currencyFormat.format(stats['profit'] ?? 0),
              color: Colors.green,
            ),
            SizedBox(height: 16),
            StatisticCard(
              title: 'Выручка',
              value: currencyFormat.format(stats['revenue'] ?? 0),
              color: Colors.blue,
            ),
            SizedBox(height: 16),
            StatisticCard(
              title: 'Затраты',
              value: currencyFormat.format(stats['cost'] ?? 0),
              color: Colors.orange,
            ),
            SizedBox(height: 16),
            StatisticCard(
              title: 'Количество заказов',
              value: (stats['orderCount'] ?? 0).toInt().toString(),
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            StatisticCard(
              title: 'Уникальных клиентов',
              value: (stats['customerCount'] ?? 0).toInt().toString(),
              color: Colors.purple,
            ),
          ],
        ),
      ),
    );
  }
}

class StatisticCard extends StatelessWidget {
  final String title, value;
  final Color color;
  const StatisticCard(
      {required this.title, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Card(
      elevation: 2,
      child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(children: [
            Text(title, style: TextStyle(fontSize: 16, color: Colors.black54)),
            SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          ])));
}

class AddComponentDialog extends StatefulWidget {
  @override
  _AddComponentDialogState createState() => _AddComponentDialogState();
}

class _AddComponentDialogState extends State<AddComponentDialog> {
  String? _selectedIngredientId;
  final _quantityController = TextEditingController();

  Future<void> _createNewIngredient() async {
    final provider = Provider.of<PastryProvider>(context, listen: false);
    final countBefore = provider.getIngredientsByType(IngredientType.ingredient).length;
    
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => IngredientEditScreen(type: IngredientType.ingredient),
      ),
    );
    
    // Проверяем что виджет ещё существует
    if (!mounted) return;
    
    // Получаем обновлённый список
    final ingredientsAfter = provider.getIngredientsByType(IngredientType.ingredient);
    
    // Если добавился новый ингредиент - выбираем его
    if (ingredientsAfter.length > countBefore) {
      final newIngredient = ingredientsAfter.last;
      setState(() {
        _selectedIngredientId = newIngredient.id;
      });
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context);
    final ingredients = provider.getIngredientsByType(IngredientType.ingredient);
    
    // Валидация: проверяем существует ли выбранный ID
    // Используем локальную переменную, чтобы не менять state в build
    String? validSelectedId = _selectedIngredientId;
    if (validSelectedId != null && !ingredients.any((ing) => ing.id == validSelectedId)) {
      validSelectedId = null;
    }
    
    // Проверяем, можно ли добавить
    final canAdd = validSelectedId != null && 
                   _quantityController.text.isNotEmpty &&
                   (double.tryParse(_quantityController.text) ?? 0) > 0;
    
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.restaurant, color: Theme.of(context).primaryColor),
          SizedBox(width: 8),
          Text('Добавить ингредиент'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dropdown с кнопкой создания
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    // Ключ для принудительного перестроения при изменении списка
                    key: ValueKey('ingredients_${ingredients.length}'),
                    value: validSelectedId,
                    decoration: InputDecoration(
                      labelText: 'Ингредиент',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    isExpanded: true,
                    hint: Text('Выберите ингредиент'),
                    items: ingredients
                        .map((ing) => DropdownMenuItem(
                              value: ing.id,
                              child: Text(ing.name, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedIngredientId = value;
                      });
                    },
                  ),
                ),
                SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    icon: Icon(Icons.add, color: Theme.of(context).primaryColor),
                    tooltip: 'Создать новый ингредиент',
                    onPressed: _createNewIngredient,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            TextField(
              controller: _quantityController,
              decoration: InputDecoration(
                labelText: 'Количество (г/шт)',
                border: OutlineInputBorder(),
                suffixText: 'г/шт',
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}), // Обновляем UI при вводе
            ),
            // Подсказка
            if (ingredients.isEmpty)
              Padding(
                padding: EdgeInsets.only(top: 12),
                child: Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.amber.shade700, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Нет ингредиентов. Нажмите "+", чтобы создать.',
                          style: TextStyle(fontSize: 12, color: Colors.amber.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Показываем выбранный ингредиент для подтверждения
            if (validSelectedId != null)
              Padding(
                padding: EdgeInsets.only(top: 12),
                child: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Выбрано: ${ingredients.firstWhere((i) => i.id == validSelectedId).name}',
                          style: TextStyle(fontSize: 12, color: Colors.green.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: canAdd
              ? () {
                  final component = RecipeComponent(
                    ingredientId: validSelectedId!,
                    quantity: double.tryParse(_quantityController.text) ?? 0,
                  );
                  Navigator.pop(context, component);
                }
              : null,
          child: Text('Добавить'),
        ),
      ],
    );
  }
}

class AddDecorationPackagingDialog extends StatefulWidget {
  final String title;
  final IngredientType type;
  
  const AddDecorationPackagingDialog({
    required this.title,
    required this.type,
  });
  
  @override
  _AddDecorationPackagingDialogState createState() =>
      _AddDecorationPackagingDialogState();
}

class _AddDecorationPackagingDialogState extends State<AddDecorationPackagingDialog> {
  String? _selectedItemId;
  final _quantityController = TextEditingController(text: '1');
  final _idGenerator = Random();

  String get _typeName {
    switch (widget.type) {
      case IngredientType.decoration:
        return 'украшение';
      case IngredientType.packaging:
        return 'упаковку';
      default:
        return 'элемент';
    }
  }

  String get _typeLabel {
    switch (widget.type) {
      case IngredientType.decoration:
        return 'Украшение';
      case IngredientType.packaging:
        return 'Упаковка';
      default:
        return 'Элемент';
    }
  }

  Future<void> _createNewItem() async {
    final provider = Provider.of<PastryProvider>(context, listen: false);
    final countBefore = provider.getIngredientsByType(widget.type).length;
    
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => IngredientEditScreen(type: widget.type),
      ),
    );
    
    if (!mounted) return;
    
    final itemsAfter = provider.getIngredientsByType(widget.type);
    
    if (itemsAfter.length > countBefore) {
      final newItem = itemsAfter.last;
      setState(() {
        _selectedItemId = newItem.id;
      });
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context);
    final items = provider.getIngredientsByType(widget.type);
    
    // Валидация выбранного ID
    String? validSelectedId = _selectedItemId;
    if (validSelectedId != null && !items.any((item) => item.id == validSelectedId)) {
      validSelectedId = null;
    }
    
    final canAdd = validSelectedId != null && 
                   _quantityController.text.isNotEmpty &&
                   (double.tryParse(_quantityController.text) ?? 0) > 0;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            widget.type == IngredientType.decoration 
                ? Icons.auto_awesome 
                : Icons.inventory_2,
            color: Theme.of(context).primaryColor,
          ),
          SizedBox(width: 8),
          Expanded(child: Text(widget.title)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    // Ключ для принудительного перестроения
                    key: ValueKey('${widget.type}_${items.length}'),
                    value: validSelectedId,
                    decoration: InputDecoration(
                      labelText: _typeLabel,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    isExpanded: true,
                    hint: Text('Выберите $_typeName'),
                    items: items
                        .map((item) => DropdownMenuItem(
                              value: item.id,
                              child: Text(
                                '${item.name} (${item.pricePerUnit.toStringAsFixed(0)} ₽)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedItemId = value;
                      });
                    },
                  ),
                ),
                SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    icon: Icon(Icons.add, color: Theme.of(context).primaryColor),
                    tooltip: 'Создать $_typeName',
                    onPressed: _createNewItem,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            TextFormField(
              controller: _quantityController,
              decoration: InputDecoration(
                labelText: 'Количество',
                border: OutlineInputBorder(),
                suffixText: 'шт',
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
            ),
            if (items.isEmpty)
              Padding(
                padding: EdgeInsets.only(top: 12),
                child: Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.amber.shade700, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Список пуст. Нажмите "+", чтобы создать $_typeName.',
                          style: TextStyle(fontSize: 12, color: Colors.amber.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Подтверждение выбора
            if (validSelectedId != null)
              Padding(
                padding: EdgeInsets.only(top: 12),
                child: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Выбрано: ${items.firstWhere((i) => i.id == validSelectedId).name}',
                          style: TextStyle(fontSize: 12, color: Colors.green.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: canAdd
              ? () {
                  final selectedItem = items.firstWhere((item) => item.id == validSelectedId);
                  final item = OrderDecorationPackagingItem(
                    id: _idGenerator.nextInt(100000).toString(),
                    itemId: validSelectedId!,
                    quantity: double.tryParse(_quantityController.text) ?? 0,
                    itemName: selectedItem.name,
                    itemPriceAtTime: selectedItem.pricePerUnit,
                  );
                  Navigator.pop(context, item);
                }
              : null,
          child: Text('Добавить'),
        ),
      ],
    );
  }
}