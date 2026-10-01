
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  
  "public": {
          Tables: {
            "business_hours": {
                  Row: {
                    "business_id": string,"closes_at": string,"day_of_week": number,"id": string,"opens_at": string
                  }
                  Insert: {
                    "business_id": string,"closes_at": string,"day_of_week": number,"id"?: string,"opens_at": string
                  }
                  Update: {
                    "business_id"?: string,"closes_at"?: string,"day_of_week"?: number,"id"?: string,"opens_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "business_hours_business_id_fkey"
      columns: ["business_id"]
isOneToOne: false
      referencedRelation: "businesses"
      referencedColumns: ["id"]
    }
                  ]
                },"business_images": {
                  Row: {
                    "alt_text": string | null,"business_id": string,"created_at": string,"display_order": number,"id": string,"placement": string,"storage_path": string
                  }
                  Insert: {
                    "alt_text"?: string | null,"business_id": string,"created_at"?: string,"display_order"?: number,"id"?: string,"placement"?: string,"storage_path": string
                  }
                  Update: {
                    "alt_text"?: string | null,"business_id"?: string,"created_at"?: string,"display_order"?: number,"id"?: string,"placement"?: string,"storage_path"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "business_images_business_id_fkey"
      columns: ["business_id"]
isOneToOne: false
      referencedRelation: "businesses"
      referencedColumns: ["id"]
    }
                  ]
                },"business_links": {
                  Row: {
                    "business_id": string,"created_at": string,"id": string,"kind": string,"updated_at": string,"url": string
                  }
                  Insert: {
                    "business_id": string,"created_at"?: string,"id"?: string,"kind": string,"updated_at"?: string,"url": string
                  }
                  Update: {
                    "business_id"?: string,"created_at"?: string,"id"?: string,"kind"?: string,"updated_at"?: string,"url"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "business_links_business_id_fkey"
      columns: ["business_id"]
isOneToOne: false
      referencedRelation: "businesses"
      referencedColumns: ["id"]
    }
                  ]
                },"businesses": {
                  Row: {
                    "address_line_1": string | null,"address_line_2": string | null,"city": string | null,"created_at": string,"description": string | null,"id": string,"is_published": boolean,"name": string,"phone": string | null,"slug": string,"state": string | null,"template": string,"updated_at": string,"zip_code": string | null
                  }
                  Insert: {
                    "address_line_1"?: string | null,"address_line_2"?: string | null,"city"?: string | null,"created_at"?: string,"description"?: string | null,"id"?: string,"is_published"?: boolean,"name": string,"phone"?: string | null,"slug": string,"state"?: string | null,"template"?: string,"updated_at"?: string,"zip_code"?: string | null
                  }
                  Update: {
                    "address_line_1"?: string | null,"address_line_2"?: string | null,"city"?: string | null,"created_at"?: string,"description"?: string | null,"id"?: string,"is_published"?: boolean,"name"?: string,"phone"?: string | null,"slug"?: string,"state"?: string | null,"template"?: string,"updated_at"?: string,"zip_code"?: string | null
                  }
                  Relationships: [
                    
                  ]
                },"memberships": {
                  Row: {
                    "business_id": string,"created_at": string,"id": string,"role": string,"user_id": string
                  }
                  Insert: {
                    "business_id": string,"created_at"?: string,"id"?: string,"role"?: string,"user_id": string
                  }
                  Update: {
                    "business_id"?: string,"created_at"?: string,"id"?: string,"role"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "memberships_business_id_fkey"
      columns: ["business_id"]
isOneToOne: false
      referencedRelation: "businesses"
      referencedColumns: ["id"]
    }
                  ]
                },"menu_categories": {
                  Row: {
                    "business_id": string,"created_at": string,"display_order": number,"id": string,"name": string,"updated_at": string
                  }
                  Insert: {
                    "business_id": string,"created_at"?: string,"display_order"?: number,"id"?: string,"name": string,"updated_at"?: string
                  }
                  Update: {
                    "business_id"?: string,"created_at"?: string,"display_order"?: number,"id"?: string,"name"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "menu_categories_business_id_fkey"
      columns: ["business_id"]
isOneToOne: false
      referencedRelation: "businesses"
      referencedColumns: ["id"]
    }
                  ]
                },"menu_items": {
                  Row: {
                    "business_id": string,"category_id": string,"created_at": string,"description": string | null,"display_order": number,"id": string,"is_available": boolean,"name": string,"price_cents": number | null,"updated_at": string
                  }
                  Insert: {
                    "business_id": string,"category_id": string,"created_at"?: string,"description"?: string | null,"display_order"?: number,"id"?: string,"is_available"?: boolean,"name": string,"price_cents"?: number | null,"updated_at"?: string
                  }
                  Update: {
                    "business_id"?: string,"category_id"?: string,"created_at"?: string,"description"?: string | null,"display_order"?: number,"id"?: string,"is_available"?: boolean,"name"?: string,"price_cents"?: number | null,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "menu_items_business_id_fkey"
      columns: ["business_id"]
isOneToOne: false
      referencedRelation: "businesses"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "menu_items_category_id_business_id_fkey"
      columns: ["category_id","business_id"]
isOneToOne: false
      referencedRelation: "menu_categories"
      referencedColumns: ["id","business_id"]
    }
                  ]
                },"platform_admins": {
                  Row: {
                    "created_at": string,"user_id": string
                  }
                  Insert: {
                    "created_at"?: string,"user_id": string
                  }
                  Update: {
                    "created_at"?: string,"user_id"?: string
                  }
                  Relationships: [
                    
                  ]
                }
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            "reorder_business_images":
{ Args: { "ordered_image_ids": (string)[],"target_business_id": string }; Returns: undefined
                           },
"reorder_menu_categories":
{ Args: { "ordered_category_ids": (string)[],"target_business_id": string }; Returns: undefined
                           },
"reorder_menu_items":
{ Args: { "ordered_item_ids": (string)[],"target_business_id": string,"target_category_id": string }; Returns: undefined
                           },
"replace_business_hours":
{ Args: { "periods": Json,"target_business_id": string }; Returns: undefined
                           }
          }
          Enums: {
            [_ in never]: never
          }
          CompositeTypes: {
            [_ in never]: never
          }
        }
}

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
  ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
      Row: infer R
    }
    ? R
    : never
  : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Insert: infer I
    }
    ? I
    : never
  : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Update: infer U
    }
    ? U
    : never
  : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
  ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
  : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
  ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
  : never

export const Constants = {
  "public": {
          Enums: {
            
          }
        }
} as const
