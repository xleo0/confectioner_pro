// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, use_key_in_widget_constructors, library_private_types_in_public_api, unnecessary_string_interpolations, unreachable_switch_default, deprecated_member_use, unnecessary_to_list_in_spreads, depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart'; // <<< ВАЖНО ДЛЯ КАЛЕНДАРЯ
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'dart:collection';
import 'dart:math';

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

// ===========================================================================
// 2. МОДЕЛИ ДАННЫХ
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
}

class RecipeComponent {
  String ingredientId;
  double quantity;

  RecipeComponent({required this.ingredientId, required this.quantity});
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
}

class Product {
  String id;
  String name;
  List<RecipeComponent> ingredients;
  int producedQuantity;

  Product({
    required this.id,
    required this.name,
    this.ingredients = const [],
    this.producedQuantity = 1,
  });

  double getCost(List<Ingredient> allIngredients) {
    double totalCost = 0.0;
    for (var component in ingredients) {
      try {
        final ingredient = allIngredients
            .firstWhere((ing) => ing.id == component.ingredientId);
        totalCost += ingredient.pricePerUnit * component.quantity;
      } catch (e) {
        // Ингредиент не найден
      }
    }
    return totalCost;
  }

  double getUnitCost(List<Ingredient> allIngredients) {
    if (producedQuantity <= 0) return 0.0;
    return getCost(allIngredients) / producedQuantity;
  }
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
}

class Order {
  String id;
  String productId;
  String customerName;
  String? customerPhone;
  double sellingPrice;
  int quantity;
  DateTime orderDate;
  OrderStatus status;
  String productName;
  List<OrderDecorationPackagingItem> decorations;
  List<OrderDecorationPackagingItem> packaging;
  String? inventoryItemId;
  double unitCostFromInventory;

  Order({
    required this.id,
    required this.productId,
    required this.customerName,
    this.customerPhone,
    required this.sellingPrice,
    required this.quantity,
    required this.orderDate,
    this.status = OrderStatus.inProgress,
    required this.productName,
    this.decorations = const [],
    this.packaging = const [],
    this.inventoryItemId,
    required this.unitCostFromInventory,
  });

  double getTotalCost(List<Ingredient> allIngredients) {
    double total = unitCostFromInventory * quantity;
    for (var decoration in decorations) {
      if (decoration.itemId != null && decoration.quantity > 0) {
        total += decoration.itemPriceAtTime * decoration.quantity * quantity;
      }
    }
    for (var pack in packaging) {
      if (pack.itemId != null && pack.quantity > 0) {
        total += pack.itemPriceAtTime * pack.quantity * quantity;
      }
    }
    return total;
  }

  double getTotalPrice() {
    return sellingPrice * quantity;
  }

  double getProfit(List<Ingredient> allIngredients) {
    return getTotalPrice() - getTotalCost(allIngredients);
  }

  double getDecorationCost() {
    double total = 0.0;
    for (var decoration in decorations) {
      if (decoration.itemId != null && decoration.quantity > 0) {
        total += decoration.itemPriceAtTime * decoration.quantity * quantity;
      }
    }
    return total;
  }

  double getPackagingCost() {
    double total = 0.0;
    for (var pack in packaging) {
      if (pack.itemId != null && pack.quantity > 0) {
        total += pack.itemPriceAtTime * pack.quantity * quantity;
      }
    }
    return total;
  }
}

// ===========================================================================
// 3. УПРАВЛЕНИЕ СОСТОЯНИЕМ (PROVIDER)
// ===========================================================================
class PastryProvider with ChangeNotifier {
  final List<Ingredient> _ingredients = [
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
  final List<Product> _products = [
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
  final List<Order> _orders = [];
  final List<InventoryItem> _inventory = [];

  UnmodifiableListView<Ingredient> get ingredients =>
      UnmodifiableListView(_ingredients);
  UnmodifiableListView<Product> get products => UnmodifiableListView(_products);
  UnmodifiableListView<Order> get orders => UnmodifiableListView(_orders);
  UnmodifiableListView<InventoryItem> get inventory =>
      UnmodifiableListView(_inventory);

  List<Ingredient> getIngredientsByType(IngredientType type) =>
      _ingredients.where((ing) => ing.type == type).toList();

  String _generateId() =>
      DateTime.now().millisecondsSinceEpoch.toString() +
      Random().nextInt(999).toString();

  void addIngredient(Ingredient ingredient) {
    ingredient.id = _generateId();
    _ingredients.add(ingredient);
    notifyListeners();
  }

  void updateIngredient(Ingredient updatedIngredient) {
    final index = _ingredients.indexWhere((i) => i.id == updatedIngredient.id);
    if (index != -1) {
      _ingredients[index] = updatedIngredient;
      notifyListeners();
    }
  }

  void deleteIngredient(String id) {
    _ingredients.removeWhere((ingredient) => ingredient.id == id);
    notifyListeners();
  }

  void addProduct(Product product) {
    product.id = _generateId();
    _products.add(product);
    notifyListeners();
  }

  void updateProduct(Product updatedProduct) {
    final index = _products.indexWhere((p) => p.id == updatedProduct.id);
    if (index != -1) {
      _products[index] = updatedProduct;
      notifyListeners();
    }
  }

  void deleteProduct(String id) {
    _products.removeWhere((product) => product.id == id);
    notifyListeners();
  }

  void addInventoryItem(InventoryItem item) {
    item.id = _generateId();
    _inventory.add(item);
    notifyListeners();
  }

  void updateInventoryItem(InventoryItem updatedItem) {
    final index = _inventory.indexWhere((i) => i.id == updatedItem.id);
    if (index != -1) {
      _inventory[index] = updatedItem;
      notifyListeners();
    }
  }

  void deleteInventoryItem(String id) {
    _inventory.removeWhere((item) => item.id == id);
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
      notifyListeners();
    } else {
      final inventoryItem = InventoryItem(
        id: '',
        productId: product.id,
        productName: product.name,
        quantity: quantity,
        productionDate: productionDate,
        unitCostAtTimeOfProduction: unitCost,
        availableQuantity: quantity,
      );
      addInventoryItem(inventoryItem);
    }
  }

  List<InventoryItem> getAvailableInventoryForProduct(String productId) =>
      _inventory
          .where((item) =>
              item.productId == productId && item.availableQuantity > 0)
          .toList();

  void addOrder(Order order) {
    order.id = _generateId();
    _orders.add(order);
    if (order.inventoryItemId != null) {
      final inventoryIndex =
          _inventory.indexWhere((inv) => inv.id == order.inventoryItemId);
      if (inventoryIndex != -1) {
        _inventory[inventoryIndex].availableQuantity -= order.quantity;
      }
    }
    notifyListeners();
  }

  void updateOrder(Order updatedOrder) {
    final index = _orders.indexWhere((o) => o.id == updatedOrder.id);
    if (index != -1) {
      final oldOrder = _orders[index];
      if (oldOrder.inventoryItemId != null) {
        final oldInventoryIndex =
            _inventory.indexWhere((inv) => inv.id == oldOrder.inventoryItemId);
        if (oldInventoryIndex != -1) {
          _inventory[oldInventoryIndex].availableQuantity += oldOrder.quantity;
        }
      }
      _orders[index] = updatedOrder;
      if (updatedOrder.inventoryItemId != null) {
        final newInventoryIndex = _inventory
            .indexWhere((inv) => inv.id == updatedOrder.inventoryItemId);
        if (newInventoryIndex != -1) {
          _inventory[newInventoryIndex].availableQuantity -=
              updatedOrder.quantity;
        }
      }
      notifyListeners();
    }
  }

  void deleteOrder(String id) {
    final orderIndex = _orders.indexWhere((order) => order.id == id);
    if (orderIndex != -1) {
      final orderToDelete = _orders[orderIndex];
      if (orderToDelete.inventoryItemId != null) {
        final inventoryIndex = _inventory
            .indexWhere((inv) => inv.id == orderToDelete.inventoryItemId);
        if (inventoryIndex != -1) {
          _inventory[inventoryIndex].availableQuantity +=
              orderToDelete.quantity;
        }
      }
      _orders.removeAt(orderIndex);
      notifyListeners();
    }
  }

  void updateOrderStatus(String orderId, OrderStatus newStatus) {
    final orderIndex = _orders.indexWhere((o) => o.id == orderId);
    if (orderIndex != -1) {
      _orders[orderIndex].status = newStatus;
      notifyListeners();
    }
  }

  Product getProductById(String id) => _products.firstWhere(
      (p) => p.id == id,
      orElse: () => Product(
          id: 'not_found', name: 'Изделие удалено', producedQuantity: 0));

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
      totalCost += order.getTotalCost(_ingredients);
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
      totalCost += order.getTotalCost(_ingredients);
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
      // <<< ВАЖНО: Добавлены делегаты локализации для работы календаря
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
      home: MainScreen(),
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
          title: Text('Кондитер Про'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary),
      body: screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today), label: 'Заказы'),
          BottomNavigationBarItem(icon: Icon(Icons.cake), label: 'Изделия'),
          BottomNavigationBarItem(
              icon: Icon(Icons.list_alt), label: 'Справочник'),
          BottomNavigationBarItem(
              icon: Icon(Icons.inventory), label: 'Запасы'),
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
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => ProductEditScreen()));
                } else if (_selectedIndex == 2) {
                  _showIngredientTypeDialog(context);
                } else if (_selectedIndex == 3) {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => AddToInventoryScreen()));
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
                          builder: (context) => IngredientEditScreen(
                              type: IngredientType.ingredient)));
                },
              ),
              ListTile(
                title: Text('Украшения'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => IngredientEditScreen(
                              type: IngredientType.decoration)));
                },
              ),
              ListTile(
                title: Text('Упаковка'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => IngredientEditScreen(
                              type: IngredientType.packaging)));
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
                onChanged: (value) =>
                    setState(() => _selectedProductId = value),
                validator: (value) =>
                    value == null ? 'Выберите изделие' : null,
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
                  if (value == null || value.isEmpty)
                    return 'Введите количество';
                  final quantity = int.tryParse(value);
                  if (quantity == null || quantity <= 0)
                    return 'Количество должно быть больше 0';
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
class OrdersScreen extends StatefulWidget {
  final Function(DateTime?) onDaySelected;
  const OrdersScreen({required this.onDaySelected});

  @override
  _OrdersScreenState createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  DateTime _selectedDay = DateTime.now();
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

  void _previousDay() {
    setState(() {
      _selectedDay = _selectedDay.subtract(Duration(days: 1));
      widget.onDaySelected(_selectedDay);
    });
  }

  void _nextDay() {
    setState(() {
      _selectedDay = _selectedDay.add(Duration(days: 1));
      widget.onDaySelected(_selectedDay);
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
      locale: Locale('ru', 'RU'),
    );
    if (picked != null) {
      setState(() {
        _selectedDay = picked;
        widget.onDaySelected(_selectedDay);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context);
    final List<Order> allOrders = List.from(provider.orders);
    List<Order> filteredOrders = List.from(allOrders);

    if (_selectedStatusFilter != null) {
      filteredOrders = filteredOrders
          .where((order) => order.status == _selectedStatusFilter)
          .toList();
    }

    filteredOrders = filteredOrders
        .where((order) => isSameDay(order.orderDate, _selectedDay))
        .toList();

    filteredOrders.sort((a, b) => b.orderDate.compareTo(a.orderDate));

    return Column(
      children: [
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
        Container(
          padding: EdgeInsets.symmetric(vertical: 8),
          color: Colors.grey.shade50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(Icons.chevron_left),
                onPressed: _previousDay,
              ),
              InkWell(
                onTap: _pickDate,
                child: Row(
                  children: [
                    Icon(Icons.calendar_month,
                        size: 20, color: Theme.of(context).primaryColor),
                    SizedBox(width: 8),
                    Text(
                      DateFormat('d MMMM yyyy', 'ru_RU').format(_selectedDay),
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.chevron_right),
                onPressed: _nextDay,
              ),
            ],
          ),
        ),
        Divider(height: 1),
        Expanded(
          child: filteredOrders.isEmpty
              ? Center(
                  child: Text('Нет заказов на этот день',
                      style: TextStyle(color: Colors.grey, fontSize: 16)))
              : ListView.builder(
                  padding: EdgeInsets.only(bottom: 80),
                  itemCount: filteredOrders.length,
                  itemBuilder: (context, index) {
                    final order = filteredOrders[index];
                    final product = provider.getProductById(order.productId);
                    return OrderCard(order: order, product: product);
                  },
                ),
        ),
      ],
    );
  }

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
          color: isSelected ? Theme.of(context).primaryColor : Colors.black),
    );
  }
}

bool isSameDay(DateTime? a, DateTime? b) {
  if (a == null || b == null) return false;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

// --- КАРТОЧКА ЗАКАЗА (ОБНОВЛЕННАЯ) ---
class OrderCard extends StatelessWidget {
  final Order order;
  final Product product;
  const OrderCard({required this.order, required this.product});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context, listen: false);
    final currencyFormat = NumberFormat.currency(locale: 'ru_RU', symbol: '₽');

    String displayProductName;
    if (product.id == 'not_found') {
      displayProductName =
          order.productName.isNotEmpty ? order.productName : 'Изделие удалено';
    } else {
      displayProductName = product.name;
    }

    final totalCost = order.getTotalCost(provider.ingredients);
    final totalPrice = order.getTotalPrice();
    final profit = order.getProfit(provider.ingredients);
    final decorationCost = order.getDecorationCost();
    final packagingCost = order.getPackagingCost();

    Color getStatusColor(OrderStatus status) {
      switch (status) {
        case OrderStatus.inProgress:
          return Colors.red;
        case OrderStatus.ready:
          return Colors.amber;
        case OrderStatus.completed:
          return Colors.green;
        default:
          return Colors.grey;
      }
    }

    IconData getStatusIcon(OrderStatus status) {
      switch (status) {
        case OrderStatus.inProgress:
          return Icons.access_time;
        case OrderStatus.ready:
          return Icons.check_circle;
        case OrderStatus.completed:
          return Icons.done_all;
        default:
          return Icons.help;
      }
    }

    String getStatusText(OrderStatus status) {
      switch (status) {
        case OrderStatus.inProgress:
          return 'В работе';
        case OrderStatus.ready:
          return 'Готов';
        case OrderStatus.completed:
          return 'Выдан';
        default:
          return 'Неизвестно';
      }
    }

    return Card(
        margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: InkWell(
          onTap: () {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) =>
                        OrderEditScreen(initialOrder: order)));
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // <<< КНОПКИ СТАТУСА ТЕПЕРЬ СВЕРХУ
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        IconButton(
                            tooltip: 'В работе',
                            icon: Icon(Icons.access_time),
                            color: order.status == OrderStatus.inProgress
                                ? Colors.red
                                : Colors.grey.shade300,
                            onPressed: () => provider.updateOrderStatus(
                                order.id, OrderStatus.inProgress)),
                        IconButton(
                            tooltip: 'Готов',
                            icon: Icon(Icons.check_circle),
                            color: order.status == OrderStatus.ready
                                ? Colors.amber
                                : Colors.grey.shade300,
                            onPressed: () => provider.updateOrderStatus(
                                order.id, OrderStatus.ready)),
                        IconButton(
                            tooltip: 'Выдан',
                            icon: Icon(Icons.done_all),
                            color: order.status == OrderStatus.completed
                                ? Colors.green
                                : Colors.grey.shade300,
                            onPressed: () => provider.updateOrderStatus(
                                order.id, OrderStatus.completed)),
                      ],
                    ),
                    IconButton(
                      icon: Icon(Icons.delete, color: Colors.red.shade400),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              title: Text('Подтвердите удаление'),
                              content: Text(
                                  'Удалить заказ для "$displayProductName"?'),
                              actions: <Widget>[
                                TextButton(
                                  child: Text('Отмена'),
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                                TextButton(
                                  child: Text('Удалить'),
                                  onPressed: () {
                                    provider.deleteOrder(order.id);
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
                Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(displayProductName,
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: getStatusColor(order.status).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(getStatusIcon(order.status),
                              color: getStatusColor(order.status), size: 16),
                          SizedBox(width: 4),
                          Text(getStatusText(order.status),
                              style: TextStyle(
                                  color: getStatusColor(order.status),
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text('Заказчик: ${order.customerName}'),
                if (order.customerPhone != null &&
                    order.customerPhone!.isNotEmpty)
                  Text('Телефон: ${order.customerPhone}'),
                SizedBox(height: 4),
                Text(
                    'Цена за единицу: ${currencyFormat.format(order.sellingPrice)}'),
                SizedBox(height: 4),
                Text('Количество: ${order.quantity}'),
                if (order.inventoryItemId != null)
                  FutureBuilder<InventoryItem?>(
                    future: () async {
                      try {
                        return provider.inventory.firstWhere(
                            (inv) => inv.id == order.inventoryItemId);
                      } catch (e) {
                        return null;
                      }
                    }(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.done &&
                          snapshot.hasData) {
                        final inventoryItem = snapshot.data!;
                        return Text(
                            'Партия: ${DateFormat.yMd('ru_RU').format(inventoryItem.productionDate)}',
                            style: TextStyle(color: Colors.blueGrey));
                      }
                      return SizedBox();
                    },
                  ),
                SizedBox(height: 4),
                Text('Общая цена: ${currencyFormat.format(totalPrice)}',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                if (order.decorations.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Украшения:',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          ...order.decorations.map((d) =>
                              Text('  ${d.itemName} (${d.quantity} г/шт)')),
                        ]),
                  ),
                if (order.packaging.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Упаковка:',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          ...order.packaging.map((p) =>
                              Text('  ${p.itemName} (${p.quantity} шт)')),
                        ]),
                  ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'Себестоимость: ${currencyFormat.format(totalCost)}'),
                      Text(
                          'Прибыль: ${currencyFormat.format(profit)}',
                          style: TextStyle(
                              color: profit >= 0 ? Colors.green : Colors.red,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ));
  }
}

// --- ЭКРАН РЕДАКТИРОВАНИЯ ЗАКАЗА ---
class OrderEditScreen extends StatefulWidget {
  final DateTime? selectedDate;
  final Order? initialOrder;
  const OrderEditScreen({this.selectedDate, this.initialOrder});
  @override
  _OrderEditScreenState createState() => _OrderEditScreenState();
}

class _OrderEditScreenState extends State<OrderEditScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedProductId;
  late TextEditingController _customerNameController;
  late TextEditingController _customerPhoneController;
  final MaskTextInputFormatter _phoneMaskFormatter = MaskTextInputFormatter(
      mask: '+7 (###) ###-##-##',
      filter: {"#": RegExp(r'[0-9]')},
      type: MaskAutoCompletionType.lazy);
  late TextEditingController _sellingPriceController;
  late TextEditingController _quantityController;

  String? _selectedInventoryItemId;
  List<OrderDecorationPackagingItem> _decorations = [];
  List<OrderDecorationPackagingItem> _packaging = [];
  bool get _isEditing => widget.initialOrder != null;

  final currencyFormat = NumberFormat.currency(locale: 'ru_RU', symbol: '₽');
  @override
  void initState() {
    super.initState();
    _selectedProductId = widget.initialOrder?.productId;
    _customerNameController =
        TextEditingController(text: widget.initialOrder?.customerName ?? '');
    _customerPhoneController = TextEditingController(
        text: widget.initialOrder?.customerPhone != null
            ? _phoneMaskFormatter
                .maskText(widget.initialOrder!.customerPhone!)
            : '');
    _sellingPriceController = TextEditingController(
        text: widget.initialOrder?.sellingPrice.toString() ?? '');
    _quantityController = TextEditingController(
        text: widget.initialOrder?.quantity.toString() ?? '1');
    _selectedInventoryItemId = widget.initialOrder?.inventoryItemId;
    if (_isEditing) {
      _decorations = List.from(widget.initialOrder!.decorations);
      _packaging = List.from(widget.initialOrder!.packaging);
    }
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _sellingPriceController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  void _addDecoration(PastryProvider provider) async {
    final result = await showDialog<OrderDecorationPackagingItem>(
        context: context,
        builder: (context) => AddDecorationPackagingDialog(
              title: 'Добавить украшение',
              items: provider.getIngredientsByType(IngredientType.decoration),
            ));
    if (result != null) {
      setState(() {
        _decorations.add(result);
      });
    }
  }

  void _addPackaging(PastryProvider provider) async {
    final result = await showDialog<OrderDecorationPackagingItem>(
        context: context,
        builder: (context) => AddDecorationPackagingDialog(
              title: 'Добавить упаковку',
              items: provider.getIngredientsByType(IngredientType.packaging),
            ));
    if (result != null) {
      setState(() {
        _packaging.add(result);
      });
    }
  }

  void _removeDecoration(OrderDecorationPackagingItem item) {
    setState(() {
      _decorations.remove(item);
    });
  }

  void _removePackaging(OrderDecorationPackagingItem item) {
    setState(() {
      _packaging.remove(item);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context, listen: false);
    double unitPrice = 0;
    double unitCost = 0;
    int quantity = 1;
    double totalPrice = 0;
    double totalCost = 0;
    double profit = 0;
    double decorationCost = 0;
    double packagingCost = 0;
    List<InventoryItem> availableInventory = [];
    if (_selectedProductId != null) {
      availableInventory =
          provider.getAvailableInventoryForProduct(_selectedProductId!);
      if (_selectedInventoryItemId != null) {
        try {
          final selectedInventoryItem = provider.inventory
              .firstWhere((item) => item.id == _selectedInventoryItemId);
          unitCost = selectedInventoryItem.unitCostAtTimeOfProduction;
        } catch (e) {
          // Партия не найдена
        }
      }
    }

    try {
      unitPrice = double.tryParse(_sellingPriceController.text) ?? 0;
      quantity = int.tryParse(_quantityController.text) ?? 1;
    } catch (e) {
      // Игнорируем ошибки парсинга
    }

    totalPrice = unitPrice * quantity;
    totalCost = unitCost * quantity;
    for (var decoration in _decorations) {
      totalCost += decoration.itemPriceAtTime * decoration.quantity * quantity;
      decorationCost +=
          decoration.itemPriceAtTime * decoration.quantity * quantity;
    }
    for (var pack in _packaging) {
      totalCost += pack.itemPriceAtTime * pack.quantity * quantity;
      packagingCost += pack.itemPriceAtTime * pack.quantity * quantity;
    }
    profit = totalPrice - totalCost;
    return Scaffold(
      appBar: AppBar(
          title: Text(_isEditing ? 'Редактировать заказ' : 'Новый заказ')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              DropdownButtonFormField<String>(
                initialValue: _selectedProductId,
                decoration: InputDecoration(
                    labelText: 'Выберите изделие',
                    border: OutlineInputBorder()),
                items: provider.products
                    .map((product) => DropdownMenuItem(
                        value: product.id, child: Text(product.name)))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedProductId = value;
                    _selectedInventoryItemId = null;
                  });
                },
                validator: (value) =>
                    value == null ? 'Выберите изделие' : null,
              ),
              SizedBox(height: 16),
              if (_selectedProductId != null)
                DropdownButtonFormField<String?>(
                  initialValue: _selectedInventoryItemId,
                  decoration: InputDecoration(
                      labelText: 'Партия из запасов',
                      border: OutlineInputBorder()),
                  items: [
                    DropdownMenuItem(
                        value: null, child: Text('Выберите партию')),
                    ...availableInventory.map((item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(
                              '${item.productName} (${item.availableQuantity} шт) - ${DateFormat.yMd('ru_RU').format(item.productionDate)}'),
                        )),
                  ],
                  onChanged: (value) => setState(() {
                    _selectedInventoryItemId = value;
                    setState(() {});
                  }),
                  validator: (value) =>
                      value == null ? 'Выберите партию' : null,
                ),
              SizedBox(height: 16),
              TextFormField(
                  controller: _customerNameController,
                  decoration: InputDecoration(
                      labelText: 'Имя клиента', border: OutlineInputBorder()),
                  validator: (value) =>
                      value!.isEmpty ? 'Введите имя' : null),
              SizedBox(height: 16),
              TextFormField(
                controller: _customerPhoneController,
                decoration: InputDecoration(
                    labelText: 'Телефон клиента (необязательно)',
                    border: OutlineInputBorder()),
                keyboardType: TextInputType.phone,
                inputFormatters: [_phoneMaskFormatter],
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _sellingPriceController,
                decoration: InputDecoration(
                    labelText: 'Цена за единицу, ₽',
                    border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
                validator: (value) =>
                    value!.isEmpty ? 'Введите цену' : null,
                onChanged: (value) => setState(() {}),
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _quantityController,
                decoration: InputDecoration(
                    labelText: 'Количество (продаваемых единиц)',
                    border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value!.isEmpty) return 'Введите количество';
                  final quantity = int.tryParse(value);
                  if (quantity == null || quantity <= 0) {
                    return 'Количество должно быть больше 0';
                  }
                  if (_selectedInventoryItemId != null) {
                    final selectedInventory = provider.inventory.firstWhere(
                        (inv) => inv.id == _selectedInventoryItemId,
                        orElse: () => InventoryItem(
                            id: '',
                            productId: '',
                            productName: '',
                            quantity: 0,
                            productionDate: DateTime.now(),
                            unitCostAtTimeOfProduction: 0));
                    if (quantity > selectedInventory.availableQuantity) {
                      return 'Недостаточно изделий в выбранной партии (${selectedInventory.availableQuantity} шт)';
                    }
                  }
                  return null;
                },
                onChanged: (value) => setState(() {}),
              ),
              SizedBox(height: 20),
              if (_selectedProductId != null &&
                  _selectedInventoryItemId != null)
                Card(
                  color: Colors.grey.shade100,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Финансовая информация:',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        Text(
                            'Цена за единицу: ${currencyFormat.format(unitPrice)}'),
                        Text(
                            'Себестоимость единицы (из партии): ${currencyFormat.format(unitCost)}'),
                        Text('Количество (продаваемых): $quantity'),
                        Divider(),
                        Text(
                            'Общая цена: ${currencyFormat.format(totalPrice)}',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                            'Общая себестоимость: ${currencyFormat.format(totalCost)}'),
                        Text(
                            'Стоимость украшений: ${currencyFormat.format(decorationCost)}'),
                        Text(
                            'Стоимость упаковки: ${currencyFormat.format(packagingCost)}'),
                        Text('Прибыль: ${currencyFormat.format(profit)}',
                            style: TextStyle(
                                color:
                                    profit >= 0 ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              SizedBox(height: 20),
              Text('Украшения',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ..._decorations.asMap().entries.map((entry) {
                int idx = entry.key;
                OrderDecorationPackagingItem item = entry.value;
                return ListTile(
                  key: ValueKey('decoration-$idx'),
                  title: Text('${item.itemName} (${item.quantity} г/шт)'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                          '${currencyFormat.format(item.itemPriceAtTime * item.quantity * quantity)}'),
                      IconButton(
                        icon: Icon(Icons.remove_circle_outline,
                            color: Colors.red.shade300),
                        onPressed: () => _removeDecoration(item),
                      ),
                    ],
                  ),
                );
              }).toList(),
              if (_decorations.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text('Украшения не добавлены',
                      style: TextStyle(color: Colors.grey)),
                ),
              ElevatedButton.icon(
                onPressed: () => _addDecoration(provider),
                icon: Icon(Icons.add),
                label: Text('Добавить украшение'),
              ),
              SizedBox(height: 16),
              Text('Упаковка', style: TextStyle(fontWeight: FontWeight.bold)),
              ..._packaging.asMap().entries.map((entry) {
                int idx = entry.key;
                OrderDecorationPackagingItem item = entry.value;
                return ListTile(
                  key: ValueKey('packaging-$idx'),
                  title: Text('${item.itemName} (${item.quantity} шт)'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                          '${currencyFormat.format(item.itemPriceAtTime * item.quantity * quantity)}'),
                      IconButton(
                        icon: Icon(Icons.remove_circle_outline,
                            color: Colors.red.shade300),
                        onPressed: () => _removePackaging(item),
                      ),
                    ],
                  ),
                );
              }).toList(),
              if (_packaging.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text('Упаковка не добавлена',
                      style: TextStyle(color: Colors.grey)),
                ),
              ElevatedButton.icon(
                onPressed: () => _addPackaging(provider),
                icon: Icon(Icons.add),
                label: Text('Добавить упаковку'),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 16)),
                child: Text('Сохранить'),
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    if (_selectedProductId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Ошибка: изделие не выбрано')));
                      return;
                    }
                    if (_selectedInventoryItemId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Ошибка: партия не выбрана')));
                      return;
                    }
                    double unitCostFromInventory = 0;
                    try {
                      final selectedInventoryItem = provider.inventory
                          .firstWhere(
                              (item) => item.id == _selectedInventoryItemId);
                      unitCostFromInventory =
                          selectedInventoryItem.unitCostAtTimeOfProduction;
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                              'Ошибка: не удалось получить себестоимость из партии')));
                      return;
                    }
                    DateTime orderDateToUse;
                    if (_isEditing) {
                      orderDateToUse = widget.initialOrder!.orderDate;
                    } else {
                      if (widget.selectedDate == null) {
                        orderDateToUse = DateTime.now();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                'Дата заказа не указана, используется текущая дата.')));
                      } else {
                        orderDateToUse = widget.selectedDate!;
                      }
                    }
                    final productForName =
                        provider.getProductById(_selectedProductId!);
                    final productNameToSave = productForName.name;
                    final order = Order(
                      id: _isEditing ? widget.initialOrder!.id : '',
                      productId: _selectedProductId!,
                      customerName: _customerNameController.text,
                      customerPhone: _customerPhoneController.text.isEmpty
                          ? null
                          : _customerPhoneController.text,
                      sellingPrice: unitPrice,
                      quantity: quantity,
                      orderDate: orderDateToUse,
                      status: _isEditing
                          ? widget.initialOrder!.status
                          : OrderStatus.inProgress,
                      productName: _isEditing
                          ? widget.initialOrder!.productName
                          : productNameToSave,
                      decorations: _decorations,
                      packaging: _packaging,
                      inventoryItemId: _selectedInventoryItemId,
                      unitCostFromInventory: unitCostFromInventory,
                    );
                    if (_isEditing) {
                      provider.updateOrder(order);
                    } else {
                      provider.addOrder(order);
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

// --- ЭКРАН ИЗДЕЛИЙ ---
class ProductsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context);
    return provider.products.isEmpty
        ? Center(
            child: Text(
                'У вас пока нет изделий.\nНажмите "+", чтобы добавить.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey)))
        : ListView.builder(
            padding: EdgeInsets.all(8),
            itemCount: provider.products.length,
            itemBuilder: (context, index) {
              final product = provider.products[index];
              final cost = product.getCost(provider.ingredients);
              final unitCost = product.getUnitCost(provider.ingredients);
              return Card(
                  elevation: 2,
                  margin: EdgeInsets.symmetric(vertical: 8),
                  child: ListTile(
                    title: Text(product.name,
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'Себестоимость (общая): ${cost.toStringAsFixed(2)} ₽'),
                        Text(
                            'Себестоимость (единица): ${unitCost.toStringAsFixed(2)} ₽'),
                        Text('Изготовлено: ${product.producedQuantity} шт'),
                      ],
                    ),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          icon: Icon(Icons.inventory,
                              color: Colors.blue.shade600),
                          tooltip: 'Добавить в запасы',
                          onPressed: () => _addToInventoryDialog(
                              context, product, provider),
                        ),
                        IconButton(
                          icon: Icon(Icons.edit, color: Colors.grey.shade600),
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => ProductEditScreen(
                                      initialProduct: product))),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, color: Colors.red.shade400),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: Text('Подтвердите удаление'),
                                  content: Text(
                                      'Удалить изделие "${product.name}"?'),
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
                                        provider.deleteProduct(product.id);
                                        Navigator.of(context).pop();
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                                'Изделие "${product.name}" удалено'),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
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

  void _addToInventoryDialog(
      BuildContext context, Product product, PastryProvider provider) {
    if (product.producedQuantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: Неверное количество изделия')));
      return;
    }

    DateTime selectedDate = DateTime.now();
    TextEditingController quantityController =
        TextEditingController(text: product.producedQuantity.toString());

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Добавить в запасы'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Изделие: ${product.name}'),
                  SizedBox(height: 10),
                  TextField(
                    controller: quantityController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: 'Количество', border: OutlineInputBorder()),
                  ),
                  SizedBox(height: 10),
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
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(DateFormat.yMd('ru_RU').format(selectedDate)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Отмена')),
                ElevatedButton(
                  onPressed: () {
                    final qty = int.tryParse(quantityController.text);
                    if (qty != null && qty > 0) {
                      try {
                        provider.addProductToInventory(
                            product.id, qty, selectedDate);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                'Добавлено в запасы: ${product.name} ($qty шт)')));
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Ошибка: ${e.toString()}')));
                      }
                    }
                  },
                  child: Text('Добавить'),
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

  bool get _isEditing => widget.initialProduct != null;
  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.initialProduct?.name ?? '');
    _producedQuantityController = TextEditingController(
        text: widget.initialProduct?.producedQuantity.toString() ?? '1');
    _ingredients = widget.initialProduct?.ingredients
            .map((c) => RecipeComponent(
                ingredientId: c.ingredientId, quantity: c.quantity))
            .toList() ??
        [];
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

  void _removeComponent(
      List<RecipeComponent> componentList, RecipeComponent component) {
    setState(() {
      componentList.remove(component);
    });
  }

  Widget _buildComponentList(String title, List<RecipeComponent> components,
      PastryProvider provider) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        IconButton(
            icon: Icon(Icons.add_circle_outline,
                color: Theme.of(context).primaryColor),
            onPressed: () => _addComponent(components)),
      ]),
      if (components.isEmpty)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text('  Компоненты не добавлены',
                style: TextStyle(color: Colors.grey))),
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
              Text('${c.quantity.toStringAsFixed(0)} г/шт',
                  style: TextStyle(fontSize: 12)),
              IconButton(
                  icon: Icon(Icons.remove_circle_outline,
                      color: Colors.red.shade300, size: 18),
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
    int producedQuantity =
        int.tryParse(_producedQuantityController.text) ?? 1;
    double totalCost = Product(
            id: '',
            name: '',
            ingredients: _ingredients,
            producedQuantity: producedQuantity)
        .getCost(provider.ingredients);
    double unitCost =
        producedQuantity > 0 ? totalCost / producedQuantity : 0;

    return Scaffold(
      appBar: AppBar(
          title: Text(
              _isEditing ? 'Редактировать изделие' : 'Новое изделие')),
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
                      contentPadding: EdgeInsets.symmetric(
                          vertical: 16.0, horizontal: 12.0)),
                  validator: (value) =>
                      value!.isEmpty ? 'Введите название' : null),
              SizedBox(height: 16),
              TextFormField(
                controller: _producedQuantityController,
                decoration: InputDecoration(
                    labelText: 'Количество изготовленных',
                    border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value!.isEmpty) return 'Введите количество';
                  final quantity = int.tryParse(value);
                  if (quantity == null || quantity <= 0) {
                    return 'Количество должно быть больше 0';
                  }
                  return null;
                },
              ),
              SizedBox(height: 20),
              _buildComponentList('Ингредиенты', _ingredients, provider),
              Divider(height: 30),
              Text(
                  'Себестоимость (общая): ${totalCost.toStringAsFixed(2)} ₽',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              Text(
                  'Себестоимость (единица): ${unitCost.toStringAsFixed(2)} ₽',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 16)),
                child: Text('Сохранить'),
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    final product = Product(
                        id: _isEditing ? widget.initialProduct!.id : '',
                        name: _nameController.text,
                        ingredients: _ingredients,
                        producedQuantity:
                            int.parse(_producedQuantityController.text));
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
}

// --- СПРАВОЧНИК ---
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
                  validator: (value) =>
                      value!.isEmpty ? 'Введите цену' : null),
              SizedBox(height: 16),
              TextFormField(
                  controller: _packageSizeController,
                  decoration: InputDecoration(
                      labelText: 'Вес/кол-во в упаковке (г/шт)',
                      border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  validator: (value) =>
                      value!.isEmpty ? 'Введите вес' : null),
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

    final availableInventory = provider.inventory
        .where((item) => item.availableQuantity > 0)
        .toList();
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
            _buildStatsTabContent(
                context, statsWeek, currencyFormat, 'за неделю'),
            _buildStatsTabContent(
                context, statsMonth, currencyFormat, 'за месяц'),
            _buildStatsTabContent(
                context, statsYear, currencyFormat, 'за год'),
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
                          value: currencyFormat
                              .format(statsAllTime['profit'] ?? 0),
                          color: Colors.green),
                      SizedBox(height: 16),
                      StatisticCard(
                          title: 'Общая выручка',
                          value: currencyFormat
                              .format(statsAllTime['revenue'] ?? 0),
                          color: Colors.blue),
                      SizedBox(height: 16),
                      StatisticCard(
                          title: 'Общие затраты',
                          value:
                              currencyFormat.format(statsAllTime['cost'] ?? 0),
                          color: Colors.orange),
                      SizedBox(height: 16),
                      StatisticCard(
                          title: 'Выполнено заказов',
                          value: (statsAllTime['orderCount'] ?? 0)
                              .toInt()
                              .toString(),
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

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context, listen: false);
    final ingredients =
        provider.getIngredientsByType(IngredientType.ingredient);
    return AlertDialog(
      title: Text('Добавить ингредиент'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(
          initialValue: _selectedIngredientId,
          hint: Text('Выберите ингредиент'),
          items: ingredients
              .map((ing) =>
                  DropdownMenuItem(value: ing.id, child: Text(ing.name)))
              .toList(),
          onChanged: (value) => setState(() => _selectedIngredientId = value),
        ),
        SizedBox(height: 8),
        TextField(
            controller: _quantityController,
            decoration: InputDecoration(labelText: 'Количество (г/шт)'),
            keyboardType: TextInputType.number),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text('Отмена')),
        ElevatedButton(
            onPressed: () {
              if (_selectedIngredientId != null &&
                  _quantityController.text.isNotEmpty) {
                final component = RecipeComponent(
                    ingredientId: _selectedIngredientId!,
                    quantity: double.tryParse(_quantityController.text) ?? 0);
                Navigator.pop(context, component);
              }
            },
            child: Text('Добавить')),
      ],
    );
  }
}

class AddDecorationPackagingDialog extends StatefulWidget {
  final String title;
  final List<Ingredient> items;
  const AddDecorationPackagingDialog(
      {required this.title, required this.items});
  @override
  _AddDecorationPackagingDialogState createState() =>
      _AddDecorationPackagingDialogState();
}

class _AddDecorationPackagingDialogState
    extends State<AddDecorationPackagingDialog> {
  String? _selectedItemId;
  final _quantityController = TextEditingController(text: '1');
  final _idGenerator = Random();
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(
          initialValue: _selectedItemId,
          hint: Text('Выберите элемент'),
          items: widget.items
              .map((item) =>
                  DropdownMenuItem(value: item.id, child: Text(item.name)))
              .toList(),
          onChanged: (value) => setState(() => _selectedItemId = value),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: _quantityController,
          decoration: InputDecoration(labelText: 'Количество (г/шт или шт)'),
          keyboardType: TextInputType.number,
        ),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text('Отмена')),
        ElevatedButton(
            onPressed: () {
              if (_selectedItemId != null &&
                  _quantityController.text.isNotEmpty) {
                final selectedItem = widget.items
                    .firstWhere((item) => item.id == _selectedItemId);
                final item = OrderDecorationPackagingItem(
                  id: _idGenerator.nextInt(100000).toString(),
                  itemId: _selectedItemId!,
                  quantity: double.tryParse(_quantityController.text) ?? 0,
                  itemName: selectedItem.name,
                  itemPriceAtTime: selectedItem.pricePerUnit,
                );
                Navigator.pop(context, item);
              }
            },
            child: Text('Добавить')),
      ],
    );
  }
}