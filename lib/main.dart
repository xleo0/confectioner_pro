// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, use_key_in_widget_constructors, library_private_types_in_public_api, unnecessary_string_interpolations, unreachable_switch_default, deprecated_member_use, unnecessary_to_list_in_spreads
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/date_symbol_data_local.dart'; // Для initializeDateFormatting
import 'package:intl/intl.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart'; // <<< ДОБАВИТЬ ИМПОРТ
import 'dart:collection';
import 'dart:math';

// ===========================================================================
// 1. ТОЧКА ВХОДА (MAIN)
// ===========================================================================
void main() async {
  // Инициализация локализации для работы с датами, временем и валютой
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

// Новый enum для типов ингредиентов
enum IngredientType { ingredient, decoration, packaging }

class Ingredient {
  String id;
  String name;
  double price;
  double packageSize; // Вес или количество в одной упаковке (г/шт)
  IngredientType type; // Тип ингредиента

  Ingredient({
    required this.id,
    required this.name,
    required this.price,
    required this.packageSize,
    this.type = IngredientType.ingredient, // По умолчанию ингредиент
  });

  double get pricePerUnit => (packageSize > 0) ? price / packageSize : 0;
}

class RecipeComponent {
  String ingredientId;
  double quantity;

  RecipeComponent({required this.ingredientId, required this.quantity});
}

// НОВАЯ МОДЕЛЬ: Запись о запасе
class InventoryItem {
  String id; // Уникальный ID записи о запасе
  String productId; // ID изделия
  String productName; // Название изделия (для быстрого доступа)
  int quantity; // Общее количество изготовленных изделий
  int availableQuantity; // Доступное для продажи количество (может уменьшаться)
  DateTime productionDate; // Дата изготовления
  double unitCostAtTimeOfProduction; // Себестоимость одной единицы на момент изготовления

  InventoryItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.productionDate,
    required this.unitCostAtTimeOfProduction,
    int? availableQuantity, // Если не задано, то равно общему количеству
  }) : availableQuantity = availableQuantity ?? quantity;
}

class Product {
  String id;
  String name;
  List<RecipeComponent> ingredients; // Только ингредиенты
  int producedQuantity; // <<< НОВОЕ ПОЛЕ: Количество изготовленных единиц

  Product({
    required this.id,
    required this.name,
    this.ingredients = const [],
    this.producedQuantity = 1, // <<< ИНИЦИАЛИЗАЦИЯ ПО УМОЛЧАНИЮ
  });

  double getCost(List<Ingredient> allIngredients) {
    double totalCost = 0.0;
    // Только ингредиенты входят в базовую себестоимость изделия
    for (var component in ingredients) {
      try {
        final ingredient =
            allIngredients.firstWhere((ing) => ing.id == component.ingredientId);
        totalCost += ingredient.pricePerUnit * component.quantity;
      } catch (e) {
        // Ингредиент не найден, пропускаем
      }
    }
    return totalCost;
  }

  // <<< НОВЫЙ МЕТОД: Себестоимость одной единицы изделия
  double getUnitCost(List<Ingredient> allIngredients) {
    if (producedQuantity <= 0) return 0.0; // Защита от деления на ноль
    return getCost(allIngredients) / producedQuantity;
  }
}

// Новый класс для хранения информации о выбранных украшениях и упаковке в заказе
class OrderDecorationPackagingItem {
  String id; // Уникальный ID для каждого элемента в списке
  String? itemId; // ID украшения или упаковки
  double quantity;

  // Сохраняем информацию на момент создания заказа
  String itemName;
  double itemPriceAtTime; // Цена за единицу на момент создания заказа

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
  String? customerPhone; // Новое поле для номера телефона
  double sellingPrice;
  int quantity; // Количество продаваемых единиц
  DateTime orderDate;
  OrderStatus status;

  // Название изделия на момент создания заказа
  String productName;

  // Списки украшений и упаковок с сохраненной информацией
  List<OrderDecorationPackagingItem> decorations;
  List<OrderDecorationPackagingItem> packaging;

  // НОВОЕ ПОЛЕ: ID записи о запасе, из которой берутся изделия
  String? inventoryItemId;

  // НОВОЕ ПОЛЕ: Себестоимость одной единицы изделия из выбранной партии на момент создания заказа
  double unitCostFromInventory;

  Order({
    required this.id,
    required this.productId,
    required this.customerName,
    this.customerPhone, // Добавлено в конструктор
    required this.sellingPrice,
    required this.quantity,
    required this.orderDate,
    this.status = OrderStatus.inProgress,
    required this.productName,
    this.decorations = const [],
    this.packaging = const [],
    this.inventoryItemId, // Добавлено в конструктор
    required this.unitCostFromInventory, // Добавлено в конструктор
  });

  // Расчет полной себестоимости заказа (изделие + украшение + упаковка)
  // ИЗМЕНЕНО: Себестоимость изделия берется из выбранной партии
  double getTotalCost(List<Ingredient> allIngredients) {
    double total = unitCostFromInventory * quantity; // Себестоимость изделий из партии
    // Добавляем стоимость украшений для всех изделий
    for (var decoration in decorations) {
      if (decoration.itemId != null && decoration.quantity > 0) {
        total += decoration.itemPriceAtTime * decoration.quantity * quantity;
      }
    }
    // Добавляем стоимость упаковок для всех изделий
    for (var pack in packaging) {
      if (pack.itemId != null && pack.quantity > 0) {
        total += pack.itemPriceAtTime * pack.quantity * quantity;
      }
    }
    return total;
  }

  // Расчет общей цены заказа
  double getTotalPrice() {
    return sellingPrice * quantity;
  }

  // Расчет прибыли
  double getProfit(List<Ingredient> allIngredients) {
    return getTotalPrice() - getTotalCost(allIngredients);
  }

  // Новые методы для получения стоимости украшений и упаковки
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
        id: 'dec2',
        name: 'Шоколадная стружка',
        price: 120,
        packageSize: 50,
        type: IngredientType.decoration),
    Ingredient(
        id: 'pack1',
        name: 'Коробка для торта',
        price: 100,
        packageSize: 1,
        type: IngredientType.packaging),
    Ingredient(
        id: 'pack2',
        name: 'Лента атласная',
        price: 50,
        packageSize: 1,
        type: IngredientType.packaging),
  ];

  final List<Product> _products = [
    Product(
        id: 'prod1',
        name: 'Торт "Медовик"',
        producedQuantity: 1, // <<< ИНИЦИАЛИЗАЦИЯ
        ingredients: [
          RecipeComponent(ingredientId: 'ing1', quantity: 300),
          RecipeComponent(ingredientId: 'ing2', quantity: 200),
          RecipeComponent(ingredientId: 'ing3', quantity: 180)
        ])
  ];

  final List<Order> _orders = [];
  final List<InventoryItem> _inventory = []; // НОВЫЙ СПИСОК ЗАПАСОВ

  UnmodifiableListView<Ingredient> get ingredients =>
      UnmodifiableListView(_ingredients);
  UnmodifiableListView<Product> get products =>
      UnmodifiableListView(_products);
  UnmodifiableListView<Order> get orders => UnmodifiableListView(_orders);
  UnmodifiableListView<InventoryItem> get inventory =>
      UnmodifiableListView(_inventory); // Геттер для запасов

  // Методы для получения ингредиентов по типу
  List<Ingredient> getIngredientsByType(IngredientType type) =>
      _ingredients.where((ing) => ing.type == type).toList();

  // --- УНИКАЛЬНЫЙ ID ---
  String _generateId() =>
      DateTime.now().millisecondsSinceEpoch.toString() +
      Random().nextInt(999).toString();

  // --- МЕТОДЫ ДЛЯ ИНГРЕДИЕНТОВ ---
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

  // --- МЕТОДЫ ДЛЯ ИЗДЕЛИЙ ---
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

  // --- МЕТОДЫ ДЛЯ ЗАПАСОВ ---
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

  // <<< НОВЫЙ МЕТОД: Добавление готового изделия в запасы
  void addProductToInventory(String productId, int quantity) {
    final product = _products.firstWhere((p) => p.id == productId, orElse: () => throw Exception('Product not found'));
    final unitCost = product.getUnitCost(_ingredients);

    if (unitCost <= 0 || quantity <= 0) {
      // Можно выбросить исключение или показать сообщение
      throw Exception('Неверные данные изделия или количество');
    }

    final inventoryItem = InventoryItem(
      id: '', // Будет установлено в addInventoryItem
      productId: product.id,
      productName: product.name,
      quantity: quantity,
      productionDate: DateTime.now(),
      unitCostAtTimeOfProduction: unitCost,
      availableQuantity: quantity, // Изначально все доступно
    );
    addInventoryItem(inventoryItem);
  }

  // Получить список доступных запасов для конкретного изделия
  List<InventoryItem> getAvailableInventoryForProduct(String productId) =>
      _inventory
          .where((item) =>
              item.productId == productId && item.availableQuantity > 0)
          .toList();

  // --- МЕТОДЫ ДЛЯ ЗАКАЗОВ ---
  void addOrder(Order order) {
    order.id = _generateId();
    _orders.add(order);
    // НОВАЯ ЛОГИКА: Уменьшить доступное количество в запасах
    if (order.inventoryItemId != null) {
      final inventoryIndex =
          _inventory.indexWhere((inv) => inv.id == order.inventoryItemId);
      if (inventoryIndex != -1) {
        _inventory[inventoryIndex].availableQuantity -= order.quantity;
        // Если доступное количество стало 0, можно удалить запись или оставить
        // Для простоты оставим запись, просто с нулевым доступным количеством
      }
    }
    notifyListeners();
  }

  void updateOrder(Order updatedOrder) {
    final index = _orders.indexWhere((o) => o.id == updatedOrder.id);
    if (index != -1) {
      // Если заказ обновляется (например, изменяется количество), нужно вернуть
      // старое количество в запасы и затем вычесть новое
      final oldOrder = _orders[index];
      if (oldOrder.inventoryItemId != null) {
        final oldInventoryIndex =
            _inventory.indexWhere((inv) => inv.id == oldOrder.inventoryItemId);
        if (oldInventoryIndex != -1) {
          _inventory[oldInventoryIndex].availableQuantity +=
              oldOrder.quantity;
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
      // Вернуть количество в запасы при удалении заказа
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

  // --- ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ---
  List<Order> getOrdersForDay(DateTime day) =>
      _orders.where((order) => isSameDay(order.orderDate, day)).toList();

  Product getProductById(String id) => _products.firstWhere(
      (p) => p.id == id,
      orElse: () => Product(id: 'not_found', name: 'Изделие удалено', producedQuantity: 0)); // <<< ДОБАВЛЕНО producedQuantity

  Ingredient getIngredientById(String id) => _ingredients.firstWhere(
      (i) => i.id == id,
      orElse: () => Ingredient(
          id: 'not_found',
          name: 'Ингредиент удален',
          price: 0,
          packageSize: 0,
          type: IngredientType.ingredient));

  // --- СТАТИСТИКА ---
  Map<String, double> getStatistics() {
    // Старая статистика для совместимости (все выполненные заказы)
    final completedOrders =
        _orders.where((o) => o.status == OrderStatus.completed);
    double totalRevenue = 0, totalCost = 0;
    for (var order in completedOrders) {
      totalRevenue += order.getTotalPrice();
      totalCost += order.getTotalCost(_ingredients); // Используем новый метод
    }
    return {
      'revenue': totalRevenue,
      'cost': totalCost,
      'profit': totalRevenue - totalCost,
      'orderCount': completedOrders.length.toDouble()
    };
  }

  // НОВАЯ СТАТИСТИКА ПО ПЕРИОДАМ
  Map<String, double> getStatisticsForPeriod(
      DateTime startDate, DateTime endDate) {
    // Фильтруем выполненные заказы по периоду
    final completedOrders = _orders
        .where((o) => o.status == OrderStatus.completed)
        .where((o) =>
            (o.orderDate.isAfter(startDate) ||
                isSameDay(o.orderDate, startDate)) &&
            (o.orderDate.isBefore(endDate) ||
                isSameDay(o.orderDate, endDate)))
        .toList();
    double totalRevenue = 0, totalCost = 0;
    Set<String> uniqueCustomers = {}; // Для подсчета уникальных клиентов
    for (var order in completedOrders) {
      totalRevenue += order.getTotalPrice();
      totalCost += order.getTotalCost(_ingredients); // Используем новый метод
      uniqueCustomers.add(order.customerName); // Добавляем имя клиента в множество
    }
    return {
      'revenue': totalRevenue,
      'cost': totalCost,
      'profit': totalRevenue - totalCost,
      'orderCount': completedOrders.length.toDouble(),
      'customerCount': uniqueCustomers.length.toDouble(), // Количество уникальных клиентов
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

  // Инициализируем дату по умолчанию, чтобы она никогда не была null
  DateTime _selectedDayForNewOrder = DateTime.now();

  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

  // Изменяем тип параметра на DateTime? и добавляем проверку
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
      IngredientsMainScreen(), // Изменено на новый экран
      InventoryScreen(), // НОВАЯ ВКЛАДКА
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
              icon: Icon(Icons.inventory), label: 'Запасы'), // НОВАЯ ВКЛАДКА
          BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart), label: 'Статистика'),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
      floatingActionButton: _selectedIndex < 4 // Показывать кнопку только на первых 4 экранах
          ? FloatingActionButton(
              child: Icon(Icons.add),
              onPressed: () {
                if (_selectedIndex == 0) {
                  // Заказы
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => OrderEditScreen(
                              selectedDate: _selectedDayForNewOrder)));
                } else if (_selectedIndex == 1) {
                  // Изделия
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => ProductEditScreen()));
                } else if (_selectedIndex == 2) {
                  // Справочник - открываем выбор типа
                  _showIngredientTypeDialog(context);
                } else if (_selectedIndex == 3) {
                  // <<< ИЗМЕНЕНО: Запасы - теперь FAB открывает новый экран
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

// <<< НОВЫЙ ЭКРАН: Добавление изделия в запасы
class AddToInventoryScreen extends StatefulWidget {
  @override
  _AddToInventoryScreenState createState() => _AddToInventoryScreenState();
}

class _AddToInventoryScreenState extends State<AddToInventoryScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedProductId;
  late TextEditingController _quantityController;

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
              Text('Выберите изделие:', style: Theme.of(context).textTheme.titleMedium),
              SizedBox(height: 8),
              DropdownButtonFormField<String>(
                isExpanded: true,
                decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Изделие'
                ),
                value: _selectedProductId,
                items: provider.products
                    .map((product) => DropdownMenuItem(
                        value: product.id, child: Text(product.name)))
                    .toList(),
                onChanged: (value) => setState(() => _selectedProductId = value),
                validator: (value) => value == null ? 'Выберите изделие' : null,
              ),
              SizedBox(height: 16),
              Text('Введите количество:', style: Theme.of(context).textTheme.titleMedium),
              SizedBox(height: 8),
              TextFormField(
                controller: _quantityController,
                decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Количество'
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Введите количество';
                  final quantity = int.tryParse(value);
                  if (quantity == null || quantity <= 0) return 'Количество должно быть больше 0';
                  return null;
                },
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate() && _selectedProductId != null) {
                    try {
                      final quantity = int.parse(_quantityController.text);
                      provider.addProductToInventory(_selectedProductId!, quantity);
                      Navigator.pop(context); // Закрываем экран
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

// --- ЭКРАН ЗАКАЗОВ (ОБНОВЛЕННЫЙ) ---
class OrdersScreen extends StatefulWidget {
  final Function(DateTime?) onDaySelected;
  const OrdersScreen({required this.onDaySelected});

  @override
  _OrdersScreenState createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  OrderStatus? _selectedStatusFilter; // Фильтр по статусу

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onDaySelected(_selectedDay!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context);

    // ИСПРАВЛЕНИЕ 1: Создаем изменяемую копию неизменяемого списка
    final List<Order> allOrders = List.from(provider.orders);

    // 1. Фильтрация по статусу (если выбран)
    // ИСПРАВЛЕНИЕ 2: Всегда начинаем с изменяемой копии
    List<Order> filteredOrders = List.from(allOrders);
    if (_selectedStatusFilter != null) {
      filteredOrders = filteredOrders // ИСПРАВЛЕНИЕ 3: Фильтруем изменяемую копию
          .where((order) => order.status == _selectedStatusFilter)
          .toList();
    }

    // 2. Фильтрация по дате (если выбрана дата)
    // ИСПРАВЛЕНИЕ: Фильтрация по дате применяется только если дата выбрана и статус не установлен
    if (_selectedDay != null && _selectedStatusFilter == null) {
      filteredOrders = filteredOrders
          .where((order) => isSameDay(order.orderDate, _selectedDay))
          .toList();
    }

    // 2. Сортировка по дате (от новых к старым)
    // ИСПРАВЛЕНИЕ 4: Теперь это безопасно
    filteredOrders.sort((a, b) => b.orderDate.compareTo(a.orderDate));

    return Column(
      children: [
        // Календарь
        TableCalendar(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          focusedDay: _focusedDay,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
              widget.onDaySelected(selectedDay);
            });
          },
          calendarStyle: CalendarStyle(
            todayDecoration: BoxDecoration(
                color: Colors.pink.shade100, shape: BoxShape.circle),
            selectedDecoration: BoxDecoration(
                color: Theme.of(context).primaryColor, shape: BoxShape.circle),
          ),
          eventLoader: (day) => provider.getOrdersForDay(day),
          locale: 'ru_RU',
          // Убираем кнопку "2 weeks"
          availableCalendarFormats: const {CalendarFormat.month: 'Месяц'},
          calendarFormat: CalendarFormat.month,
        ),
        const Divider(),
        // Выпадающий список для фильтрации по статусу
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Фильтр по статусу:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              DropdownButton<OrderStatus?>(
                hint: Text('Все'),
                value: _selectedStatusFilter,
                items: [
                  DropdownMenuItem(value: null, child: Text('Все')),
                  ...OrderStatus.values.map((status) => DropdownMenuItem(
                        value: status,
                        child: Text(_getStatusText(status)),
                      )),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedStatusFilter = value;
                  });
                },
              ),
            ],
          ),
        ),
        SizedBox(height: 8),
        Expanded(
          child: filteredOrders.isEmpty
              ? Center(
                  child: Text('Заказы не найдены',
                      style: TextStyle(color: Colors.grey)))
              : ListView.builder(
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

  String _getStatusText(OrderStatus status) {
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
}

// --- ВСПОМОГАТЕЛЬНАЯ ФУНКЦИЯ ДЛЯ СРАВНЕНИЯ ДАТ ---
bool isSameDay(DateTime? a, DateTime? b) {
  if (a == null || b == null) return false;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

// --- ЭКРАН ДОБАВЛЕНИЯ/РЕДАКТИРОВАНИЯ ЗАКАЗА ---
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
  late TextEditingController _customerPhoneController; // Новый контроллер для телефона
  final MaskTextInputFormatter _phoneMaskFormatter =
      MaskTextInputFormatter( // <<< НОВЫЙ ФОРМАТТЕР
          mask: '+7 (###) ###-##-##',
          filter: {"#": RegExp(r'[0-9]')},
          type: MaskAutoCompletionType.lazy);
  late TextEditingController _sellingPriceController;
  late TextEditingController _quantityController; // Количество продаваемых единиц

  // НОВАЯ ПЕРЕМЕННАЯ: для выбора партии из запасов
  String? _selectedInventoryItemId;

  // Списки для украшений и упаковок
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
            ? _phoneMaskFormatter.maskText(
                widget.initialOrder!.customerPhone!) // Применяем маску к существующему значению
            : ''); // Инициализация телефона с форматтером
    _sellingPriceController = TextEditingController(
        text: widget.initialOrder?.sellingPrice.toString() ?? '');
    _quantityController = TextEditingController(
        text: widget.initialOrder?.quantity.toString() ?? '1');

    // Инициализация выбранной партии из запасов
    _selectedInventoryItemId = widget.initialOrder?.inventoryItemId;

    // Инициализация значений для украшений и упаковок
    if (_isEditing) {
      _decorations = List.from(widget.initialOrder!.decorations);
      _packaging = List.from(widget.initialOrder!.packaging);
    }
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose(); // Освобождение ресурсов
    _sellingPriceController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  // Методы для добавления/удаления украшений и упаковок
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

    // Получаем текущую себестоимость и прибыль
    double unitPrice = 0;
    double unitCost = 0; // Себестоимость одной единицы из выбранной партии
    int quantity = 1;
    double totalPrice = 0;
    double totalCost = 0;
    double profit = 0;
    double decorationCost = 0;
    double packagingCost = 0;

    // Получаем доступные запасы для выбранного изделия
    List<InventoryItem> availableInventory = [];
    if (_selectedProductId != null) {
      availableInventory =
          provider.getAvailableInventoryForProduct(_selectedProductId!);
      // Если выбрана партия, получаем её себестоимость
      if (_selectedInventoryItemId != null) {
        try {
          final selectedInventoryItem = provider.inventory
              .firstWhere((item) => item.id == _selectedInventoryItemId);
          unitCost = selectedInventoryItem.unitCostAtTimeOfProduction;
        } catch (e) {
          // Партия не найдена, оставляем unitCost = 0
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
    totalCost = unitCost * quantity; // Себестоимость изделий
    for (var decoration in _decorations) {
      totalCost += decoration.itemPriceAtTime * decoration.quantity * quantity;
      decorationCost += decoration.itemPriceAtTime * decoration.quantity * quantity;
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
                    labelText: 'Выберите изделие', border: OutlineInputBorder()),
                items: provider.products
                    .map((product) => DropdownMenuItem(
                        value: product.id, child: Text(product.name)))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedProductId = value;
                    // Сбросить выбранную партию при смене изделия
                    _selectedInventoryItemId = null;
                  });
                },
                validator: (value) => value == null ? 'Выберите изделие' : null,
              ),
              SizedBox(height: 16),

              // НОВОЕ ПОЛЕ: Выбор партии из запасов
              if (_selectedProductId != null)
                DropdownButtonFormField<String?>(
                  initialValue: _selectedInventoryItemId,
                  decoration: InputDecoration(
                      labelText: 'Партия из запасов',
                      border: OutlineInputBorder()),
                  items: [
                    DropdownMenuItem(value: null, child: Text('Выберите партию')),
                    ...availableInventory.map((item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(
                              '${item.productName} (${item.availableQuantity} шт) - ${DateFormat.yMd('ru_RU').format(item.productionDate)}'),
                        )),
                  ],
                  onChanged: (value) => setState(() {
                    _selectedInventoryItemId = value;
                    // При изменении партии пересчитываем себестоимость
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
                  controller: _customerPhoneController, // Поле для телефона
                  decoration: InputDecoration(
                      labelText: 'Телефон клиента (необязательно)',
                      border: OutlineInputBorder()),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [_phoneMaskFormatter], // <<< ПРИМЕНЕНИЕ ФОРМАТТЕРА
              ),
              SizedBox(height: 16),
              TextFormField(
                  controller: _sellingPriceController,
                  decoration: InputDecoration(
                      labelText: 'Цена за единицу, ₽',
                      border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  validator: (value) => value!.isEmpty ? 'Введите цену' : null,
                  onChanged: (value) => setState(() {}), // Перерисовываем для обновления итогов
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
                    // НОВАЯ ВАЛИДАЦИЯ: Проверка наличия в выбранной партии
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
                  onChanged: (value) => setState(() {}), // Перерисовываем для обновления итогов
              ),
              SizedBox(height: 20),

              // Отображение себестоимости и прибыли
              if (_selectedProductId != null && _selectedInventoryItemId != null)
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
                                color: profit >= 0 ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              SizedBox(height: 20),

              // Выбор украшений
              Text('Украшения', style: TextStyle(fontWeight: FontWeight.bold)),
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

              // Выбор упаковки
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
                    // Проверяем, что изделие и партия выбраны
                    if (_selectedProductId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Ошибка: изделие не выбрано')));
                      return;
                    }
                    if (_selectedInventoryItemId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Ошибка: партия не выбрана')));
                      return;
                    }

                    // Получаем себестоимость единицы из выбранной партии
                    double unitCostFromInventory = 0;
                    try {
                      final selectedInventoryItem = provider.inventory
                          .firstWhere(
                              (item) => item.id == _selectedInventoryItemId);
                      unitCostFromInventory =
                          selectedInventoryItem.unitCostAtTimeOfProduction;
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content:
                              Text('Ошибка: не удалось получить себестоимость из партии')));
                      return;
                    }

                    // Безопасно определяем дату заказа
                    DateTime orderDateToUse;
                    if (_isEditing) {
                      orderDateToUse = widget.initialOrder!.orderDate;
                    } else {
                      // При создании нового заказа selectedDate ДОЛЖЕН быть передан
                      if (widget.selectedDate == null) {
                        // Если по какой-то причине он null, используем текущую дату и покажем предупреждение
                        orderDateToUse = DateTime.now();
                        // Можно показать пользователю уведомление
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                'Дата заказа не указана, используется текущая дата.')));
                      } else {
                        orderDateToUse = widget.selectedDate!;
                      }
                    }

                    // Получаем изделие для названия
                    final productForName =
                        provider.getProductById(_selectedProductId!);
                    final productNameToSave = productForName.name; // Сохраняем название

                    final order = Order(
                      id: _isEditing ? widget.initialOrder!.id : '',
                      productId: _selectedProductId!, // Проверено выше
                      customerName: _customerNameController.text,
                      customerPhone: _customerPhoneController.text.isEmpty
                          ? null
                          : _customerPhoneController.text, // Сохранение телефона
                      sellingPrice: unitPrice,
                      quantity: quantity,
                      orderDate: orderDateToUse, // Используем безопасно определенную дату
                      status: _isEditing
                          ? widget.initialOrder!.status
                          : OrderStatus.inProgress,
                      // Сохраняем название изделия на момент создания заказа
                      productName: _isEditing
                          ? widget.initialOrder!.productName
                          : productNameToSave,
                      // Сохраняем информацию об украшениях и упаковке
                      decorations: _decorations,
                      packaging: _packaging,
                      // НОВОЕ ПОЛЕ: Сохраняем выбранную партию
                      inventoryItemId: _selectedInventoryItemId,
                      // НОВОЕ ПОЛЕ: Сохраняем себестоимость единицы из партии
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
              final unitCost = product.getUnitCost(provider.ingredients); // <<< СЕБЕСТОИМОСТЬ ЕДИНИЦЫ
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
                            'Себестоимость (единица): ${unitCost.toStringAsFixed(2)} ₽'), // <<< ОТОБРАЖЕНИЕ
                        Text('Изготовлено: ${product.producedQuantity} шт'), // <<< ОТОБРАЖЕНИЕ
                      ],
                    ),
                    trailing: Wrap(
                      spacing: 8, // Небольшое расстояние между кнопками
                      children: [
                        IconButton(
                          icon: Icon(Icons.inventory,
                              color: Colors.blue.shade600),
                          tooltip: 'Добавить в запасы',
                          onPressed: () => _addToInventory(context, product, provider), // <<< НОВАЯ КНОПКА
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
                            // Диалог подтверждения удаления
                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: Text('Подтвердите удаление'),
                                  content: Text(
                                      'Вы уверены, что хотите удалить изделие "${product.name}"?'),
                                  actions: <Widget>[
                                    TextButton(
                                      child: Text('Отмена'),
                                      onPressed: () {
                                        Navigator.of(context)
                                            .pop(); // Закрываем диалог
                                      },
                                    ),
                                    TextButton(
                                      child: Text('Удалить'),
                                      onPressed: () {
                                        provider.deleteProduct(product.id);
                                        Navigator.of(context)
                                            .pop(); // Закрываем диалог
                                        // Показываем уведомление
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

  // <<< НОВЫЙ МЕТОД: Добавление в запасы
  void _addToInventory(BuildContext context, Product product, PastryProvider provider) {
    final unitCost = product.getUnitCost(provider.ingredients);
    if (unitCost <= 0 || product.producedQuantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: Неверные данные изделия')));
      return;
    }
    final inventoryItem = InventoryItem(
      id: '', // Будет установлено в addInventoryItem
      productId: product.id,
      productName: product.name,
      quantity: product.producedQuantity,
      productionDate: DateTime.now(),
      unitCostAtTimeOfProduction: unitCost,
      availableQuantity: product.producedQuantity, // Изначально все доступно
    );
    provider.addInventoryItem(inventoryItem);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Добавлено в запасы: ${product.name} (${product.producedQuantity} шт)')));
  }
}

// --- ЭКРАН ДОБАВЛЕНИЯ/РЕДАКТИРОВАНИЯ ИЗДЕЛИЯ ---
class ProductEditScreen extends StatefulWidget {
  final Product? initialProduct;
  const ProductEditScreen({this.initialProduct});

  @override
  _ProductEditScreenState createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _producedQuantityController; // <<< НОВЫЙ КОНТРОЛЛЕР
  late List<RecipeComponent> _ingredients;

  bool get _isEditing => widget.initialProduct != null;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.initialProduct?.name ?? '');
    _producedQuantityController = TextEditingController(
        text: widget.initialProduct?.producedQuantity.toString() ??
            '1'); // <<< ИНИЦИАЛИЗАЦИЯ
    _ingredients = widget.initialProduct?.ingredients
            .map((c) => RecipeComponent(
                ingredientId: c.ingredientId, quantity: c.quantity))
            .toList() ??
        [];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _producedQuantityController.dispose(); // <<< ОСВОБОЖДЕНИЕ
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
        // Фильтруем только ингредиенты для выбора в изделии
        final ingredient = provider
            .getIngredientsByType(IngredientType.ingredient)
            .firstWhere((ing) => ing.id == c.ingredientId,
                orElse: () => Ingredient(
                    id: 'not_found',
                    name: 'Не найден',
                    price: 0,
                    packageSize: 0,
                    type: IngredientType.ingredient));
        final ingredientName = ingredient.name;
        return ListTile(
          key: ValueKey('$title-$idx'), // Уникальный ключ для каждого ListTile
          title: Text(ingredientName),
          trailing: Row(
            mainAxisSize: MainAxisSize.min, // ВАЖНО: ограничиваем ширину Row
            children: [
              Text('${c.quantity.toStringAsFixed(0)} г/шт',
                  style: TextStyle(fontSize: 12)),
              IconButton(
                  icon: Icon(Icons.remove_circle_outline,
                      color: Colors.red.shade300, size: 18),
                  onPressed: () => _removeComponent(components, c),
                  padding: EdgeInsets.zero, // Уменьшаем padding для компактности
                  constraints: BoxConstraints(
                      minHeight: 24, minWidth: 24)), // Уменьшаем размер кнопки
            ],
          ),
        );
      }).toList(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context);

    // Recalculate total cost and unit cost on each build
    int producedQuantity =
        int.tryParse(_producedQuantityController.text) ?? 1; // <<< ПАРСИНГ
    double totalCost = Product(
            id: '',
            name: '',
            ingredients: _ingredients,
            producedQuantity: producedQuantity) // <<< ПЕРЕДАЧА
        .getCost(provider.ingredients);
    double unitCost = producedQuantity > 0 ? totalCost / producedQuantity : 0; // <<< РАСЧЕТ

    return Scaffold(
      appBar: AppBar(
          title:
              Text(_isEditing ? 'Редактировать изделие' : 'Новое изделие')),
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
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0)),
                  validator: (value) => value!.isEmpty ? 'Введите название' : null),
              SizedBox(height: 16),
              TextFormField(
                  // <<< НОВОЕ ПОЛЕ
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
                  'Итоговая себестоимость (общая): ${totalCost.toStringAsFixed(2)} ₽',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              Text(
                  'Итоговая себестоимость (единица): ${unitCost.toStringAsFixed(2)} ₽',
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
                        producedQuantity: int.parse(
                            _producedQuantityController.text)); // <<< СОХРАНЕНИЕ
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

// --- ГЛАВНЫЙ ЭКРАН СПРАВОЧНИКА ---
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

// --- ЭКРАН СПИСКА ИНГРЕДИЕНТОВ ПО ТИПУ ---
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
        return 'Неизвестно';
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context);
    final ingredients = provider.getIngredientsByType(type);

    return ingredients.isEmpty
        ? Center(
            child: Text('${_getTypeName(type)} пусты.\nНажмите "+", чтобы добавить.',
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
                      spacing: 8, // Небольшое расстояние между кнопками
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
                            // Диалог подтверждения удаления
                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: Text('Подтвердите удаление'),
                                  content: Text(
                                      'Вы уверены, что хотите удалить ${_getTypeName(ing.type).toLowerCase()} "${ing.name}"?'),
                                  actions: <Widget>[
                                    TextButton(
                                      child: Text('Отмена'),
                                      onPressed: () {
                                        Navigator.of(context)
                                            .pop(); // Закрываем диалог
                                      },
                                    ),
                                    TextButton(
                                      child: Text('Удалить'),
                                      onPressed: () {
                                        provider.deleteIngredient(ing.id);
                                        Navigator.of(context)
                                            .pop(); // Закрываем диалог
                                        // Показываем уведомление
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                                '${_getTypeName(ing.type)} "${ing.name}" удален(а)'),
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
}

// --- ЭКРАН ДОБАВЛЕНИЯ/РЕДАКТИРОВАНИЯ ИНГРЕДИЕНТА ---
class IngredientEditScreen extends StatefulWidget {
  final Ingredient? initialIngredient;
  final IngredientType type; // Новый параметр для типа ингредиента
  const IngredientEditScreen({this.initialIngredient, required this.type});

  @override
  _IngredientEditScreenState createState() => _IngredientEditScreenState();
}

class _IngredientEditScreenState extends State<IngredientEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  late TextEditingController _packageSizeController;
  late IngredientType _ingredientType; // Локальная переменная для типа

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
    // Устанавливаем тип из параметров или из существующего ингредиента
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
    String getTypeName(IngredientType type) {
      switch (type) {
        case IngredientType.ingredient:
          return 'ингредиент';
        case IngredientType.decoration:
          return 'украшение';
        case IngredientType.packaging:
          return 'упаковку';
        default:
          return 'элемент';
      }
    }

    return Scaffold(
      appBar: AppBar(
          title:
              Text(_isEditing ? 'Редактировать' : 'Новый ${getTypeName(_ingredientType)}')),
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
                  validator: (value) => value!.isEmpty ? 'Введите название' : null),
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
                        type: _ingredientType); // Используем локальную переменную типа
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

// --- НОВЫЙ ЭКРАН: ЗАПАСЫ ---
class InventoryScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context);
    final currencyFormat = NumberFormat.currency(locale: 'ru_RU', symbol: '₽');

    // Фильтруем записи с количеством > 0
    final availableInventory = provider.inventory
        .where((item) => item.availableQuantity > 0)
        .toList();

    return availableInventory.isEmpty
        ? Center(
            child: Text('Запасы пусты.\nСоздайте изделие и добавьте его в запасы.',
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
                                    'Вы уверены, что хотите удалить запись о запасе "${item.productName}" от ${DateFormat.yMd('ru_RU').format(item.productionDate)}?'),
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
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                        content: Text('Запись удалена'),
                                        backgroundColor: Colors.green,
                                      ));
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

// --- ЭКРАН СТАТИСТИКИ (ОБНОВЛЕННЫЙ) ---
class StatisticsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context);
    final now = DateTime.now();
    final startOfWeek =
        now.subtract(Duration(days: now.weekday - 1)); // Понедельник текущей недели
    final startOfMonth = DateTime(now.year, now.month, 1);
    final startOfYear = DateTime(now.year, 1, 1);

    final statsWeek = provider.getStatisticsForPeriod(startOfWeek, now);
    final statsMonth = provider.getStatisticsForPeriod(startOfMonth, now);
    final statsYear = provider.getStatisticsForPeriod(startOfYear, now);

    // Для совместимости с предыдущим экраном
    final statsAllTime = provider.getStatistics();

    final currencyFormat = NumberFormat.currency(locale: 'ru_RU', symbol: '₽');

    return DefaultTabController(
      length: 4, // 4 вкладки: Неделя, Месяц, Год, Всё время
      child: Scaffold(
        appBar: AppBar(
          bottom: TabBar(
            isScrollable: true, // Позволяет прокручивать вкладки, если их много
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
            // --- СТАТИСТИКА ЗА НЕДЕЛЮ ---
            _buildStatsTabContent(
                context, statsWeek, currencyFormat, 'за неделю'),
            // --- СТАТИСТИКА ЗА МЕСЯЦ ---
            _buildStatsTabContent(
                context, statsMonth, currencyFormat, 'за месяц'),
            // --- СТАТИСТИКА ЗА ГОД ---
            _buildStatsTabContent(
                context, statsYear, currencyFormat, 'за год'),
            // --- СТАТИСТИКА ЗА ВСЁ ВРЕМЯ ---
            SingleChildScrollView(
              // Добавлен SingleChildScrollView
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

  // --- ВСПОМОГАТЕЛЬНЫЙ МЕТОД ДЛЯ СТАТИСТИКИ ---
  Widget _buildStatsTabContent(BuildContext context, Map<String, double> stats,
      NumberFormat currencyFormat, String periodLabel) {
    return SingleChildScrollView(
      // Добавлен SingleChildScrollView
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Статистика (выполненные заказы) $periodLabel',
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

// ===========================================================================
// 6. ВИДЖЕТЫ
// ===========================================================================
class OrderCard extends StatelessWidget {
  final Order order;
  final Product product;
  const OrderCard({required this.order, required this.product});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PastryProvider>(context, listen: false);
    final currencyFormat = NumberFormat.currency(locale: 'ru_RU', symbol: '₽');

    // Определяем, какое имя изделия отображать
    String displayProductName;
    if (product.id == 'not_found') {
      // Изделие было удалено, используем сохраненное имя
      displayProductName = order.productName.isNotEmpty
          ? order.productName
          : 'Изделие удалено';
    } else {
      // Изделие существует, используем текущее имя
      displayProductName = product.name;
    }

    // Рассчитываем себестоимость и прибыль
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
          return Icons.access_time; // Иконка "часы" для "в работе"
        case OrderStatus.ready:
          return Icons.check_circle; // Иконка "галочка" для "готов"
        case OrderStatus.completed:
          return Icons.done_all; // Иконка "галочки" для "выдан"
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
              crossAxisAlignment: CrossAxisAlignment.start, // <--- ИСПРАВЛЕНО: Добавлена запятая после этого свойства
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(displayProductName,
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    // Индикатор статуса
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
                Text(
                    'Количество (продаваемых): ${order.quantity}'),
                // НОВАЯ ИНФОРМАЦИЯ: Отображение партии из запасов
                if (order.inventoryItemId != null)
                  FutureBuilder<InventoryItem?>(
                    future: () async {
                      try {
                        return provider.inventory
                            .firstWhere(
                                (inv) => inv.id == order.inventoryItemId);
                      } catch (e) {
                        return null; // Если партия не найдена
                      }
                    }(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.done &&
                          snapshot.hasData) {
                        final inventoryItem = snapshot.data!;
                        return Text(
                            'Партия: ${DateFormat.yMd('ru_RU').format(inventoryItem.productionDate)}',
                            style: TextStyle(color: Colors.blueGrey));
                      } else if (snapshot.hasError) {
                        return Text('Ошибка загрузки партии',
                            style: TextStyle(color: Colors.red));
                      }
                      return Text('Загрузка партии...',
                          style: TextStyle(color: Colors.grey));
                    },
                  ),
                SizedBox(height: 4),
                Text(
                    'Общая цена: ${currencyFormat.format(totalPrice)}',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                // Отображаем информацию об украшениях
                if (order.decorations.isNotEmpty) SizedBox(height: 4),
                if (order.decorations.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Украшения:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      ...order.decorations.map((decoration) =>
                          Text('  ${decoration.itemName} (${decoration.quantity} г/шт)')),
                    ],
                  ),
                // Отображаем информацию об упаковке
                if (order.packaging.isNotEmpty) SizedBox(height: 4),
                if (order.packaging.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Упаковка:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      ...order.packaging.map((pack) =>
                          Text('  ${pack.itemName} (${pack.quantity} шт)')),
                    ],
                  ),
                SizedBox(height: 4),
                Text(
                    'Дата: ${DateFormat.yMd('ru_RU').format(order.orderDate)}'),
                // Отображаем себестоимость и прибыль
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
                          'Общая себестоимость: ${currencyFormat.format(totalCost)}',
                          style: TextStyle(fontSize: 14)),
                      Text(
                          'Стоимость украшений: ${currencyFormat.format(decorationCost)}',
                          style: TextStyle(fontSize: 14)),
                      Text(
                          'Стоимость упаковки: ${currencyFormat.format(packagingCost)}',
                          style: TextStyle(fontSize: 14)),
                      Text('Прибыль: ${currencyFormat.format(profit)}',
                          style: TextStyle(
                              fontSize: 14,
                              color: profit >= 0 ? Colors.green : Colors.red,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                SizedBox(height: 8),

                // Кнопки изменения статуса и удаления
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
                    // Кнопка удаления заказа
                    IconButton(
                      icon: Icon(Icons.delete, color: Colors.red.shade400),
                      onPressed: () {
                        // Диалог подтверждения удаления
                        showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              title: Text('Подтвердите удаление'),
                              content: Text(
                                  'Вы уверены, что хотите удалить заказ №${order.id.substring(0, 6)} для "$displayProductName"?'),
                              actions: <Widget>[
                                TextButton(
                                  child: Text('Отмена'),
                                  onPressed: () {
                                    Navigator.of(context)
                                        .pop(); // Закрываем диалог
                                  },
                                ),
                                TextButton(
                                  child: Text('Удалить'),
                                  onPressed: () {
                                    provider.deleteOrder(order.id);
                                    Navigator.of(context)
                                        .pop(); // Закрываем диалог
                                    // Показываем уведомление
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      SnackBar(
                                        content: Text('Заказ удален'),
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
                )
              ],
            ),
          ),
        ));
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
    // Только ингредиенты доступны для выбора в изделии
    final ingredients = provider.getIngredientsByType(IngredientType.ingredient);

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
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Отмена')),
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

// Новый виджет для добавления украшений и упаковки
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
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Отмена')),
        ElevatedButton(
            onPressed: () {
              if (_selectedItemId != null &&
                  _quantityController.text.isNotEmpty) {
                final selectedItem = widget.items
                    .firstWhere((item) => item.id == _selectedItemId);
                final item = OrderDecorationPackagingItem(
                    id: _idGenerator.nextInt(100000).toString(), // Генерируем уникальный ID
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