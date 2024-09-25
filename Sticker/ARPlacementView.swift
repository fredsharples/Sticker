//
//  ARPlacementView.swift
//  Sticker
//
//  Created by Fred Sharples on 9/25/24.
//

import SwiftUI
   import ARKit

   struct ARPlacementView: View {
       let imageIndex: Int
       
       var body: some View {
           VStack {
               Text("AR View for Image \(imageIndex)")
               // This is where you'd implement your ARKit view
           }
           .navigationTitle("Place Object")
       }
   }

   struct ARPlacementView_Previews: PreviewProvider {
       static var previews: some View {
           ARPlacementView(imageIndex: 1)
       }
   }
