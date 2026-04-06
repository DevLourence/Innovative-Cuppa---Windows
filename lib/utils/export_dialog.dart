import 'package:flutter/material.dart';

class ExportDialog {
  static Future<List<Map<String, dynamic>>?> showItemSelection(
    BuildContext context, 
    List<Map<String, dynamic>> items, 
    Color accent
  ) async {
    List<Map<String, dynamic>> selectedItems = List.from(items);
    
    return await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Select items to include in export', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 18)),
              content: SizedBox(
                width: 400,
                height: 400,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => setState(() => selectedItems = List.from(items)),
                          child: Text('Select All', style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
                        ),
                        TextButton(
                          onPressed: () => setState(() => selectedItems.clear()),
                          child: Text('Clear All', style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const Divider(),
                    Expanded(
                      child: ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final isSelected = selectedItems.contains(item);
                          return CheckboxListTile(
                            activeColor: accent,
                            title: Text(item['name'] ?? 'Unknown Item', style: const TextStyle(fontSize: 14)),
                            value: isSelected,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  selectedItems.add(item);
                                } else {
                                  selectedItems.remove(item);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: Text('Cancel', style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                  onPressed: selectedItems.isEmpty ? null : () => Navigator.pop(context, selectedItems),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Export PDF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      }
    );
  }
}
