//
//  CustomView8.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView8: View {
    @State public var text1Text: String = "Hottest Banker in H.K."
    @State public var text2Text: String = "Corporate Poll"
    var body: some View {
        VStack(alignment: .center) {
            Text(text1Text)
                .foregroundColor(Color(red: 0.25, green: 0.25, blue: 0.25, opacity: 1.00))
                .font(.custom("HelveticaNeue-Bold", size: 22))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
            Text(text2Text)
                .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.54, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 16))
                .lineLimit(1)
                .frame(height: 17, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .frame(width: 272.694, height: 38, alignment: .topLeading)
    }
}

struct CustomView8_Previews: PreviewProvider {
    static var previews: some View {
        CustomView8()
    }
}
